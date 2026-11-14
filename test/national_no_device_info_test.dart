import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/device_probe_card.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/second_device_slot.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_limits.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';
import 'visual_perm/visual_perm_harness.dart' as vp;

/// المشروع الوطنيّ بلا «معلومات الجهاز» (المالك ١٤ نوفمبر: «وبالتحديث الجديد المشروع الوطني نلغي منه معلومات الجهاز… لان هم بالاصل
/// ماعدهم منجمنت حتى لايصير ضغط بالصفحه»): جهاز مشتركه تديره الشركة ولا يصله الوكيل — فلا كرت «معلومات الجهاز» ولا «الجهاز الثاني»
/// بصفحة مشتركه، ولا موجة فحصٍ على قائمته، ولا «فحص الأجهزة» (الرادار) لجلسته. غيره (ساس، ايرث لنك، فايبر اكس، نبض…) كما كان.
const _idx = '13293073';

Map<String, Object?> _row() => {
      'idx': _idx,
      'username': 'FBG885F15P1',
      'firstname': 'مريم',
      'lastname': 'عبد الله',
      'phone': '07701000001',
      'profile_name': 'Basic',
      'profile_id': 46517085,
      'expiration': '2026-11-20 10:00:00',
      'remaining_days': 19,
      'online_status': 1,
      'ip': '10.20.30.40',
      'enabled': 1,
      'notes': '0',
    };

Subscriber _sub({String? companyKey}) {
  final s = Subscriber.fromJson(Map<String, dynamic>.from(_row()));
  return companyKey == null ? s : s.withCompany(companyKey);
}

MergedCompany _company(MergedProvider provider, String code) => MergedCompany(
      key: 'c0123456789ab',
      code: code,
      username: 'u',
      name: code,
      provider: provider,
      colorIndex: 0,
      adminId: '$code:1',
      ns: code,
      currency: 'IQD',
      home: false,
      status: MergedStatus.ok,
      index: 0,
    );

void main() {
  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  test('الجلسة: الوطنيّ بقديمه وجديده بلا أجهزة مشتركين — وغيره كما كان', () {
    for (final p in ['watani', 'ftth']) {
      ProviderService.debugSet(p);
      expect(sessionHasNoSubscriberDevices, isTrue, reason: p);
      expect(subscriberDevicesHidden(_sub()), isTrue, reason: p);
    }
    for (final p in ['nabd', 'accessgate', 'cloudsaas', 'fiberx', 'earthlink', 'sas4', null]) {
      ProviderService.debugSet(p);
      expect(sessionHasNoSubscriberDevices, isFalse, reason: '$p');
      expect(subscriberDevicesHidden(_sub()), isFalse, reason: '$p');
    }
  });

  test('«كل الشركات»: الحكم بشركة الصفّ لا بالجلسة — الوطنيّ بلا أجهزة، وغيره وما لا تُعرف شركته كما كان', () {
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.kit, 'watani')), isTrue);
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.kit, 'Watani')), isTrue);
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.ftth, 'ftth-iq')), isTrue);
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.kit, 'nabd')), isFalse);
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.sas4, 'ftth')), isFalse, reason: 'فايبر الجزيرة ساسٌ حقيقيّ');
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.sas4, 'supernet')), isFalse);
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.earthlink, 'earthlink')), isFalse);
    expect(companyHasNoSubscriberDevices(_company(MergedProvider.fiberx, 'fiberx')), isFalse);
    // صفٌّ مربوطٌ بشركةٍ ليست في القائمة (لم تُجلب بعد): جلسة الوطنيّ لا تحكمه — كما كان
    ProviderService.debugSet('watani');
    expect(subscriberDevicesHidden(_sub(companyKey: 'cffffffffffff')), isFalse);
  });

  group('صفحة المشترك', () {
    setUpAll(simSetUpAll);

    const v = SimVariant(430, dark: false);

    Future<void> open(WidgetTester t, {required String provider, required String label, required String adminId}) async {
      await simSetUp(secure: {'auth.admin_id': adminId, 'auth.admin_username': 'owner'});
      SubscribersApi.clearAllCaches();
      DeviceConfigApi.clearAllCaches();
      await DeviceProbeApi.clearAllCaches();
      ProviderService.debugSet(provider, label: label);
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: const {'subscribers.view': true});
      // الفحص من الهاتف لا يخرج للشبكة في الاختبار — ويُعدّ
      DeviceProbeApi.debugRunProbe = (ip) async {
        probes.add(ip);
        return null;
      };
      DeviceProbeApi.debugConnectTime = (_) async => null;
      await pumpSim(t, v, home: (_) => SubscriberDetailScreen(sub: _sub()), settle: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 25));
      DeviceProbeApi.debugRunProbe = null;
      DeviceProbeApi.debugConnectTime = null;
    }

    setUp(() => probes.clear());

    testWidgets('الوطنيّ: لا «معلومات الجهاز» ولا «الجهاز الثاني» ولا فحص لعنوان المشترك', (t) async {
      await open(t, provider: 'watani', label: 'المشروع الوطني', adminId: 'watani:2963757');
      expect(find.text('معلومات الجهاز', skipOffstage: false), findsNothing);
      expect(find.byType(DeviceProbeCard, skipOffstage: false), findsNothing);
      expect(find.byType(SecondDeviceSlot, skipOffstage: false), findsNothing);
      expect(probes, isEmpty, reason: 'لا كرت ⇒ لا فحص من الهاتف');
      await close(t);
    });

    testWidgets('شركةٌ مُضافة أخرى (نبض): «معلومات الجهاز» و«الجهاز الثاني» كما كانا', (t) async {
      await open(t, provider: 'nabd', label: 'نبض', adminId: 'nabd:77');
      expect(find.text('معلومات الجهاز', skipOffstage: false), findsOneWidget);
      expect(find.byType(SecondDeviceSlot, skipOffstage: false), findsOneWidget);
      await close(t);
    });
  });

  group('قائمة المشتركين', () {
    setUpAll(vp.visualSetUpAll);

    const nationalOwner = vp.Scenario(id: 'N_watani_owner', title: 'مالك المشروع الوطنيّ', actor: vp.Actor.owner, provider: 'watani');

    Future<int> openList(WidgetTester t, vp.Scenario s) async {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
      // المتّصلون بعناوين — كاختبار الرادار: لو دخلوا الموجة لسُئلت أجهزتهم
      final saved = [for (final m in vp.fixtureSubscribers) (has: m.containsKey('ip'), ip: m['ip'])];
      addTearDown(() {
        for (var i = 0; i < vp.fixtureSubscribers.length; i++) {
          saved[i].has ? vp.fixtureSubscribers[i]['ip'] = saved[i].ip : vp.fixtureSubscribers[i].remove('ip');
        }
      });
      for (final m in vp.fixtureSubscribers) {
        if (m['online_status'] == 1) m['ip'] = '10.9.9.${m['idx']}';
      }
      var calls = 0;
      DeviceProbeApi.debugRunProbe = (ip) async {
        calls++;
        return null;
      };
      DeviceProbeApi.debugConnectTime = (_) async => null;
      addTearDown(() {
        DeviceProbeApi.debugRunProbe = null;
        DeviceProbeApi.debugConnectTime = null;
      });
      final server = await vp.visualSetUp(s);
      await DeviceProbeApi.clearAllCaches();
      DeviceConfigApi.clearAllCaches();
      await vp.pumpVisual(t, vp.phone, home: (_) => const SubscribersScreen());
      await vp.settle(t, seconds: 3);
      // سجلّ الخادم الوهميّ: «METHOD path → status»
      deviceConfigCalls = server.log.where((l) => RegExp(r'^GET /api/subscribers/[^/ ]+/device ').hasMatch(l)).length;
      return calls;
    }

    Future<void> closeList(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await vp.visualTearDown();
    }

    testWidgets('جلسة الوطنيّ: لا موجة فحص (لا جهاز يُسأل ولا طلب إعداد جهازٍ لكلّ مشترك) ولا زرّ «فحص الأجهزة»', (t) async {
      final calls = await openList(t, nationalOwner);
      expect(calls, 0, reason: 'لا جهاز يُسأل لمشتركي الوطنيّ');
      expect(deviceConfigCalls, 0, reason: 'ولا طلب «إعداد الجهاز» لكلّ مشترك');
      expect(find.byKey(const ValueKey('subs-general-check')), findsNothing, reason: 'الرادار لا يظهر لجلسة الوطنيّ');
      await closeList(t);
    });

    testWidgets('جلسة ساس (المرجع): الموجة تسأل أجهزة المتّصلين والرادار ظاهر — كما كان', (t) async {
      final calls = await openList(t, vp.s1bSasOwner);
      expect(calls, greaterThan(0));
      expect(find.byKey(const ValueKey('subs-general-check')), findsOneWidget);
      await closeList(t);
    });
  });
}

final probes = <String>[];
int deviceConfigCalls = 0;
