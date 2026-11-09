import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/network_devices/check/devices_check_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/device_vitals.dart';
import 'package:rad_mysvcs/services/devices_check.dart';
import 'package:rad_mysvcs/services/device_sweep_coordinator.dart';
import 'package:rad_mysvcs/services/devices_check_runner.dart';
import 'package:rad_mysvcs/services/merged_devices_check.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الفحص الشامل» في «كل الشركات» (٧ نوفمبر): المفتوحة بفحصها المعتاد، وكلّ شركةٍ أخرى بفحص الخادم عبر VPN شركتها — كلّ نداءٍ
/// بمفتاحها، وبلا طريقٍ تُسمّى ولا تُعدّ أجهزتها طافية، وغائبٌ عن النتيجة «لم يُقرأ».
const _kA = 'c0000000000aa';
const _kB = 'c0000000000bb';
const _kE = 'c0000000000ee';

MergedCompany _co(String key, String name, String admin, int i) => MergedCompany(
      key: key,
      code: 'x',
      username: 'u$i',
      name: name,
      provider: MergedProvider.sas4,
      colorIndex: i,
      adminId: admin,
      ns: key,
      currency: 'IQD',
      home: false,
      status: MergedStatus.ok,
      index: i,
    );

NetworkDevice _d(int id, String admin, String name, {String ip = '10.0.0.1', String type = 'router'}) => NetworkDevice(
      id: id,
      adminId: admin,
      name: name,
      type: type,
      brand: 'mikrotik',
      ip: ip,
      port: 8728,
      protocol: 'api',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 10, 1),
    );

final _a = _co(_kA, 'سوبرنت', 'supernet:12', 0);
final _b = _co(_kB, 'الجزيرة', 'jt:22', 1);
final _e = _co(_kE, 'ايرث لنك', 'earthlink:77', 3);

void main() {
  final calls = <String>[];
  late Map<String, MergedVpnRoute> routes;
  late Map<String, ({String? id, String? error})> starts;
  late Map<String, VpnNowResult> results;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    routes = {_kB: MergedVpnRoute.linked, _kE: MergedVpnRoute.missing};
    starts = {_kB: (id: 'chk-b', error: null)};
    results = {
      _kB: const VpnNowResult(ok: true, message: 'تم', devices: [
        VpnDeviceResult(id: 201, alive: true, ms: 9),
        VpnDeviceResult(id: 203, alive: false),
      ]),
    };
    // كلّ نداءٍ لشركةٍ أخرى يجب أن يكون داخل نطاقها الموجَّه
    String tag(String what, MergedCompany c) {
      expect(CompanyRoute.currentKey, c.key, reason: '$what «${c.name}» خارج نطاق شركته');
      calls.add('$what:${c.key}');
      return c.key;
    }

    MergedDevicesCheckRunner.pollEvery = const Duration(milliseconds: 1);
    MergedDevicesCheckRunner.debugRoute = (c) async => routes[tag('route', c)] ?? MergedVpnRoute.unknown;
    MergedDevicesCheckRunner.debugStart = (c) async => starts[tag('start', c)] ?? (id: null, error: 'رفض الخادم');
    MergedDevicesCheckRunner.debugPoll = (c, id) async {
      tag('poll', c);
      return (done: true, progress: null, result: results[c.key]);
    };
    MergedDevicesCheckRunner.debugLimits = (c) async {
      tag('limits', c);
      return (limits: const CheckLimits(), complete: c.key != _kE);
    };
    MergedDevicesCheckRunner.debugSubscribers = (c) async {
      tag('subs', c);
      return [Subscriber.fromJson({'idx': 7, 'username': 'ali', 'last_mac': 'AA:BB:CC:00:11:22'})];
    };
    // المفتوحة: الفحص المعتاد بلا شبكة
    DevicesCheckRunner.debugLimits = () async => const CheckLimits();
    DevicesCheckRunner.debugSubscribers = () async => const [];
    DevicesCheckRunner.debugProbe = (d) async => (status: 'offline', responseMs: null, packetLoss: 100.0, serviceOk: null);
  });

  tearDown(() {
    MergedDevicesCheckRunner.debugRoute = null;
    MergedDevicesCheckRunner.debugStart = null;
    MergedDevicesCheckRunner.debugPoll = null;
    MergedDevicesCheckRunner.debugLimits = null;
    MergedDevicesCheckRunner.debugSubscribers = null;
    MergedDevicesCheckRunner.pollEvery = const Duration(seconds: 2);
    DevicesCheckRunner.debugLimits = null;
    DevicesCheckRunner.debugSubscribers = null;
    DevicesCheckRunner.debugProbe = null;
  });

  List<MergedCheckPart> parts() => [
        MergedCheckPart(company: _a, open: true, devices: [_d(101, 'supernet:12', 'راوتر المركز')]),
        MergedCheckPart(company: _b, devices: [
          _d(201, 'jt:22', 'راوتر الجزيرة', ip: '192.168.88.1'),
          _d(202, 'jt:22', 'سكتر الجزيرة', ip: '192.168.88.20', type: 'sector'),
          _d(203, 'jt:22', 'سويج التوزيع', ip: '192.168.88.2', type: 'switch'),
        ]),
        MergedCheckPart(company: _e, devices: [_d(301, 'earthlink:77', 'برج ايرث لنك', ip: '172.16.0.1')]),
      ];

  test('المراجعة: قراءة المفتوحة التي وصلت بعد السقف (بعد انتهاء الجولة) تحلّ محلّ سطرها في «كل الشركات» أيضاً', () async {
    final late = Completer<ProbeResult>();
    DevicesCheckRunner.debugProbe = (d) async => (status: 'online', responseMs: 3, packetLoss: 0.0, serviceOk: true);
    DevicesCheckRunner.debugFetch = (d) => late.future;
    DevicesCheckRunner.debugTimes = (soft: const Duration(milliseconds: 50), hard: const Duration(milliseconds: 150));
    addTearDown(() {
      DevicesCheckRunner.debugFetch = null;
      DevicesCheckRunner.debugTimes = null;
    });
    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false);
    await r.run();
    expect(r.running, isFalse);
    expect(r.reports[101]!.state, CheckState.unread);
    expect(r.reports[101]!.findings.single.text, startsWith('بطيء — لم تكتمل قراءته خلال'));
    late.complete(const ProbeResult(vitals: [], detail: DeviceDetail(glance: DeviceGlance(cpu: 4, uptimeSec: 86400)), counters: {}));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(r.reports[101]!.state, CheckState.ok, reason: 'كانت تبقى «لم يُقرأ» — المستمع فُكّ بانتهاء الجولة');
    expect(r.reports[101]!.cpu, 4);
    r.dispose();
  });

  test('المراجعة الثانية: القسم يُمسك ما دام الهاتف يقرأ المفتوحة — لا طول فحص الخادم للشركات الأخرى، ولا أبداً لشركةٍ أخرى وحدها',
      () async {
    expect(DeviceSweep.suspended, isFalse);
    final openGate = Completer<void>();
    final serverGate = Completer<void>();
    DevicesCheckRunner.debugProbe = (d) async {
      await openGate.future;
      return (status: 'offline', responseMs: null, packetLoss: 100.0, serviceOk: null);
    };
    MergedDevicesCheckRunner.debugPoll = (c, id) async {
      await serverGate.future; // فحص الخادم لشركةٍ أخرى — دقائق
      return (done: true, progress: null, result: results[c.key]);
    };
    addTearDown(() {
      if (!openGate.isCompleted) openGate.complete();
      if (!serverGate.isCompleted) serverGate.complete();
    });
    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 20));

    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false);
    final hold = CheckSectionHold(r);
    final f = r.run();
    await tick();
    expect(DeviceSweep.suspended, isTrue, reason: 'الهاتف يقرأ أجهزة المفتوحة');
    openGate.complete();
    for (var i = 0; i < 50 && r.reports[101] == null; i++) {
      await tick();
    }
    await tick();
    expect(r.running, isTrue, reason: 'الجزيرة ما زالت تُفحص على الخادم');
    expect(DeviceSweep.suspended, isFalse, reason: 'الهاتف لا يقرأ شيئاً الآن — جولة الحال والتنبيهات تعود');
    serverGate.complete();
    await f;
    hold.dispose();
    r.dispose();

    // «افحص سكتر» لجهاز شركةٍ أخرى: فاحصٌ بجزءٍ بعيدٍ وحده — لا يمسك القسم لحظةً
    final serverGate2 = Completer<void>();
    MergedDevicesCheckRunner.debugPoll = (c, id) async {
      await serverGate2.future;
      return (done: true, progress: null, result: results[c.key]);
    };
    addTearDown(() {
      if (!serverGate2.isCompleted) serverGate2.complete();
    });
    final solo = MergedDevicesCheckRunner([
      MergedCheckPart(company: _b, devices: [_d(202, 'jt:22', 'سكتر الجزيرة', ip: '192.168.88.20', type: 'sector')])
    ], openViaVpn: false);
    final h2 = CheckSectionHold(solo);
    final f2 = solo.run();
    await tick();
    expect(solo.running, isTrue);
    expect(DeviceSweep.suspended, isFalse);
    serverGate2.complete();
    await f2;
    h2.dispose();
    solo.dispose();
    expect(DeviceSweep.suspended, isFalse);
  });

  test('كلّ شركةٍ بطريقها: المفتوحة محلّيّاً، والجزيرة عبر VPN شركتها، وايرث لنك بلا طريق تُسمّى', () async {
    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false);
    await r.run();
    // المفتوحة: فحصها المعتاد (لا يردّ ⇒ طافي)
    expect(r.reports[101]?.state, CheckState.down);
    expect(r.states[_kA]!.status, MergedCheckStatus.done);
    // الجزيرة: من نتيجة الخادم — 201 حيّ، 203 طافٍ، و202 الغائب عن النتيجة «لم يُقرأ» لا «طافي»
    expect(r.reports[201]?.state, isNot(CheckState.down));
    expect(r.reports[203]?.state, CheckState.down);
    expect(r.reports[202]?.state, CheckState.unread);
    expect(r.states[_kB]!.status, MergedCheckStatus.done);
    expect(r.states[_kB]!.viaVpn, isTrue);
    // ايرث لنك: بلا طريق ⇒ تُسمّى، ولا فحص ولا تقرير لأجهزتها
    expect(r.states[_kE]!.status, MergedCheckStatus.noVpn);
    expect(r.states[_kE]!.message, contains('تحتاج VPN'));
    expect(r.reports.containsKey(301), isFalse);
    expect(calls.where((c) => c.endsWith(_kE)), ['route:$_kE'], reason: 'بلا طريق: لا حدود ولا بدء فحص');
    expect(calls.where((c) => c.endsWith(_kA)), isEmpty, reason: 'المفتوحة لا تُطلب موجَّهة');
    expect(r.running, isFalse);
    expect(r.error, isNull);
  });

  test('تعذّر السؤال عن الطريق أو رفض بدء الفحص ⇒ الشركة «تعذّر» برسالته، والبقيّة تكمل', () async {
    routes[_kE] = MergedVpnRoute.unknown;
    starts[_kB] = (id: null, error: 'الـVPN ما اتّصل الآن — حاول بعد قليل');
    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false);
    await r.run();
    expect(r.states[_kB]!.status, MergedCheckStatus.failed);
    expect(r.states[_kB]!.message, 'الـVPN ما اتّصل الآن — حاول بعد قليل');
    expect(r.states[_kE]!.status, MergedCheckStatus.failed);
    expect(r.states[_kE]!.message, contains('تعذّر التحقّق'));
    expect(r.reports.keys, [101], reason: 'لا تقرير لشركةٍ لم تُفحص');
  });

  test('نتيجة الخادم «لم ينجح» ⇒ رسالته باسم الشركة، لا أجهزةٌ طافية', () async {
    results[_kB] = const VpnNowResult(ok: false, message: 'النفق سقط أثناء الفحص');
    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false);
    await r.run();
    expect(r.states[_kB]!.status, MergedCheckStatus.failed);
    expect(r.states[_kB]!.message, 'النفق سقط أثناء الفحص');
    expect(r.reports.keys.where((id) => id >= 200 && id < 300), isEmpty);
  });

  test('المفتوحة خارج شبكتها بلا طريق ⇒ تُقال ولا تُفحص، والشركات الأخرى تُفحص عبر VPN شركاتها', () async {
    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false, openOffNetwork: true);
    await r.run();
    expect(r.states[_kA]!.status, MergedCheckStatus.noVpn);
    expect(r.states[_kA]!.message, contains('خارج شبكتك'));
    expect(r.reports.containsKey(101), isFalse);
    expect(r.states[_kB]!.status, MergedCheckStatus.done);
  });

  test('مشترك صفٍّ في جهاز شركةٍ أخرى من قائمة شركته (بمفتاحها) — لا من المفتوحة', () async {
    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false);
    await r.run();
    expect(r.isRemote(201), isTrue);
    expect(r.isRemote(101), isFalse);
    final s = r.subscriberOn(201, 'ali');
    expect(s?.companyKey, _kB);
    expect(r.subscriberOn(301, 'ali'), isNull, reason: 'ايرث لنك لم تُفحص');
  });

  test('الحدود الافتراضيّة مُعلَنة لشركةٍ تعذّرت قراءة إعداداتها', () async {
    routes[_kE] = MergedVpnRoute.linked;
    starts[_kE] = (id: 'chk-e', error: null);
    results[_kE] = const VpnNowResult(ok: true, message: 'تم', devices: [VpnDeviceResult(id: 301, alive: true, ms: 12)]);
    final r = MergedDevicesCheckRunner(parts(), openViaVpn: false);
    await r.run();
    expect(r.states[_kE]!.status, MergedCheckStatus.done);
    expect(r.states[_kE]!.defaultLimits, isTrue);
    expect(r.states[_kB]!.defaultLimits, isFalse);
  });

  group('الشاشة', () {
    setUpAll(visualSetUpAll);

    testWidgets('بطاقة «الشركات» بحال كلّ شركة، وشارة الشركة على كرت الجهاز', (t) async {
      await visualSetUp(s1bSasOwner);
      MergedMode.reset();
      MergedMode.data.value = MergedCompaniesData.from({
        'routing': true,
        'writes': true,
        'companies': [
          {'key': _kA, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'color_index': 0},
          {'key': _kB, 'code': 'jt', 'username': 'u1', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'b', 'color_index': 1},
          {'key': _kE, 'code': 'earthlink', 'username': 'u3', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'color_index': 3},
        ],
      });
      final ps = parts();
      await pumpVisual(t, const VisualDevice('', Size(390, 1800), 1),
          home: (_) => DevicesCheckScreen(
                devices: [for (final p in ps) ...p.devices],
                viaVpn: false,
                runner: MergedDevicesCheckRunner(ps, openViaVpn: false),
              ));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await settle(t, seconds: 2);
      expect(find.byKey(const ValueKey('check-companies')), findsOneWidget);
      // التنبيه باسم الشركة: سطرها في بطاقة «الشركات» (الاسم ثمّ السبب)
      final row = find.byKey(const ValueKey('check-company-$_kE'));
      expect(find.descendant(of: row, matching: find.text('ايرث لنك')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.textContaining('تحتاج VPN')), findsOneWidget);
      expect(find.byKey(const ValueKey('check-card-201')), findsOneWidget);
      expect(find.byKey(const ValueKey('check-card-301')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('check-card-201')), matching: find.text('الجزيرة')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      MergedMode.reset();
      await visualTearDown();
    });

    testWidgets('الضغط على شركةٍ بعد الفحص يعرض أجهزتها وحدها وعدّاداتها — والضغط ثانيةً يعيد الكلّ', (t) async {
      // ٨ نوفمبر — المالك: «خلي امكانيه ان ينقر ع الشركه ويعرض بس الاجهزه بعد نتيجه الفحص»
      await visualSetUp(s1bSasOwner);
      MergedMode.reset();
      MergedMode.data.value = MergedCompaniesData.from({
        'routing': true,
        'writes': true,
        'companies': [
          {'key': _kA, 'code': 'supernet', 'username': 'u0', 'name': 'سوبرنت', 'status': 'ok', 'admin_id': 'supernet:12', 'ns': 'a', 'color_index': 0},
          {'key': _kB, 'code': 'jt', 'username': 'u1', 'name': 'الجزيرة', 'status': 'ok', 'admin_id': 'jt:22', 'ns': 'b', 'color_index': 1},
          {'key': _kE, 'code': 'earthlink', 'username': 'u3', 'name': 'ايرث لنك', 'status': 'ok', 'admin_id': 'earthlink:77', 'ns': 'e', 'color_index': 3},
        ],
      });
      final ps = parts();
      await pumpVisual(t, const VisualDevice('', Size(390, 2200), 1),
          home: (_) => DevicesCheckScreen(
                devices: [for (final p in ps) ...p.devices],
                viaVpn: false,
                runner: MergedDevicesCheckRunner(ps, openViaVpn: false),
              ));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await settle(t, seconds: 2);
      Finder card(int id) => find.byKey(ValueKey('check-card-$id'));
      int countOf(String state) {
        final chip = find.byKey(ValueKey('check-count-$state'));
        // «الحال فقط» (٩ نوفمبر) شريحتها حين يوجد منها وحده
        if (chip.evaluate().isEmpty) return 0;
        final texts = t.widgetList<Text>(find.descendant(of: chip, matching: find.byType(Text))).map((w) => w.data).toList();
        return int.parse(texts.first!);
      }

      expect(card(101), findsOneWidget);
      expect(card(201), findsOneWidget);
      expect(find.text('اضغط شركةً لعرض أجهزتها وحدها'), findsOneWidget);
      final all = CheckState.values.map((s) => countOf(s.name)).fold<int>(0, (a, b) => a + b);
      expect(all, 4, reason: '101 + ثلاثة الجزيرة');

      await t.tap(find.byKey(const ValueKey('check-company-$_kB')));
      await settle(t, seconds: 1);
      expect(card(101), findsNothing, reason: 'جهاز سوبرنت يختفي');
      expect(card(201), findsOneWidget);
      expect(card(203), findsOneWidget);
      expect(CheckState.values.map((s) => countOf(s.name)).fold<int>(0, (a, b) => a + b), 3, reason: 'عدّادات الجزيرة وحدها');
      expect(find.text('«الجزيرة» وحدها — اضغطها ثانيةً لعرض الكلّ'), findsOneWidget);
      expect(find.text('معروضة'), findsOneWidget);

      // ايرث لنك بلا نتائج (تحتاج VPN) ⇒ لا تُختار
      await t.tap(find.byKey(const ValueKey('check-company-$_kE')));
      await settle(t, seconds: 1);
      expect(card(201), findsOneWidget, reason: 'الاختيار باقٍ على الجزيرة');

      await t.tap(find.byKey(const ValueKey('check-company-$_kB')));
      await settle(t, seconds: 1);
      expect(card(101), findsOneWidget, reason: 'الضغط ثانيةً يعيد الكلّ');
      expect(find.text('معروضة'), findsNothing);
      await t.pumpWidget(const SizedBox());
      MergedMode.reset();
      await visualTearDown();
    });
  });
}
