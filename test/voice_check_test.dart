import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';
import 'package:rad_mysvcs/services/voice/voice_check.dart';
import 'package:rad_mysvcs/services/voice/voice_command.dart';
import 'package:rad_mysvcs/services/voice/voice_resolver.dart';
import 'package:rad_mysvcs/services/vpn_now.dart';

/// الأمر الصوتيّ — الفحص و«كل الشركات» (٨ نوفمبر — المالك: «البحث الصوتي ان يتعمم على جميع الشركات… جلب اسماء الاجهزه…
/// والبحث باسم الجهاز… فحص المشترك فلان… الكارت مباشره يجاوبه قبل يا اما مخلص متصل ومخلص طافي اذا متصل وفعال شنو حاله السي سي
/// كيو، حاله الاشاره اذا كان موجود مانجمنت… يقول افحص سكتر فلان… يجيب له الكارت مباشره يعطي نتيجه الجهاز»):
///   ١. الفهم: «افحص المشترك فلان»/«حالة فلان» ⇒ فحص المشترك؛ «افحص سكتر فلان» ⇒ الجهاز؛ «افحص فلان» بلا نوع ⇒ الاثنان.
///   ٢. «كل الشركات»: المشتركون والأجهزة من كلّ الشركات، كلٌّ بشركته.
///   ٣. الجواب: حاله فوراً (فعّال/منتهي، متّصل/غير متّصل الآن)، ثمّ جهازه إن كان متّصلاً وفعّالاً — من شبكتك، وإلّا عبر VPN
///      شركته، وإلّا قسمه بكلمات «الفحص العامّ» وسببه (١٠ نوفمبر — كان «بلا إدارة»: «جهازه ما ردّ — …»، «لم يُفحص — …»).
Subscriber _sub(String u, {bool online = true, int days = 20, bool enabled = true, String? company}) => Subscriber.fromJson({
      'username': u,
      'firstname': u,
      'lastname': '',
      'online_status': online ? 1 : 0,
      'remaining_days': days,
      'enabled': enabled,
      'ip_address': '10.0.0.7',
    }).withCompany(company);

UbiquitiStatus _ubnt(int sig, int ccq) => UbiquitiStatus(
    hostname: 'Nano-7', firmware: 'XC.v8', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
    ccqPercent: ccq, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1,
    lanPorts: const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)], peerMac: null, peerCount: 1,
    baseUrl: 'http://x');

MergedCompany _co(String key, String name) => MergedCompany.listFrom([
      {'key': key, 'code': 'x', 'username': 'u', 'name': name, 'status': 'ok', 'admin_id': name, 'ns': key},
    ]).single;

NetworkDevice _dev(int id, String name, {String type = 'sector'}) => NetworkDevice(
      id: id,
      adminId: 'a',
      name: name,
      type: type,
      brand: 'ubnt',
      ip: '10.1.0.$id',
      port: 443,
      protocol: 'https',
      hasCredentials: true,
      lastStatus: 'online',
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  VoiceIntent p(String s) => VoiceCommand.parse(s);

  group('الفهم', () {
    test('«افحص المشترك فلان» و«حالة فلان» ⇒ فحص المشترك', () {
      final a = p('افحص المشترك علي حسين');
      expect([a.action, a.query], [VoiceAction.checkSubscriber, 'علي حسين']);
      expect(p('افحص جهاز المشترك علي').query, 'علي', reason: '«جهاز المشترك» = جهازه، لا جهازٌ باسم علي');
      expect(p('افحص جهاز المشترك علي').action, VoiceAction.checkSubscriber);
      expect([p('شنو حالة علي حسين').action, p('شنو حالة علي حسين').query], [VoiceAction.checkSubscriber, 'علي حسين']);
      expect(p('حالة علي').action, VoiceAction.checkSubscriber);
      expect(p('شوف حالة زينب').action, VoiceAction.checkSubscriber);
      expect(p('افحص يوزر ali.home').query, 'ali home');
    });

    test('«افحص سكتر فلان» جهاز كما كان؛ «افحص فلان» بلا نوع ⇒ الاثنان؛ «افحص» وحدها ⇒ الشامل', () {
      final d = p('افحص سكتر الشمال');
      expect([d.action, d.query, d.deviceKind], [VoiceAction.checkDevice, 'الشمال', 'sector']);
      expect(p('افحص جهاز علي').action, VoiceAction.checkDevice);
      final c = p('افحص علي حسين');
      expect([c.action, c.query], [VoiceAction.check, 'علي حسين']);
      expect(p('افحص').action, VoiceAction.checkAll);
      expect(p('فحص شامل').action, VoiceAction.checkAll);
    });
  });

  group('«كل الشركات» — الأسماء من كلّ الشركات', () {
    final a = _co('c0000000000a1', 'سوبرنت');
    final b = _co('c0000000000b1', 'ايرث لنك');
    tearDown(() {
      VoiceResolver.mergedOn = () => false;
    });

    test('المشتركون: صفوف الشركتين بمفاتيحها — اليوزر نفسه بشركتين مرشّحان', () async {
      VoiceResolver.mergedOn = () => true;
      VoiceResolver.mergedSubscribers = (q) async => [
            _sub('ali.home', company: a.key),
            _sub('ali.home', company: b.key),
            _sub('zaid', company: b.key),
          ];
      final m = await VoiceResolver.subscribers('ali home');
      expect(m.items.map((x) => x.item.companyKey).toSet(), {a.key, b.key});
      expect(m.sure, isFalse, reason: 'اثنان بالدرجة نفسها — يختار');
    });

    test('الأجهزة: أسماء أجهزة كلّ الشركات، وشركة كلّ جهاز ومفتوحتها', () async {
      VoiceResolver.mergedOn = () => true;
      VoiceResolver.mergedDevices = () async => [
            (device: _dev(1, 'سكتر المركز'), company: (company: a, open: true)),
            (device: _dev(2, 'سكتر الشمال'), company: (company: b, open: false)),
          ];
      final m = await VoiceResolver.devices('الشمال', kind: 'sector');
      expect(m.items.first.item.id, 2);
      expect(m.sure, isTrue);
      expect(VoiceResolver.companyOfDevice(2)?.company.key, b.key);
      expect(VoiceResolver.companyOfDevice(2)?.open, isFalse, reason: 'جهاز شركةٍ أخرى يُفحص عبر VPN شركته');
      expect(VoiceResolver.companyOfDevice(1)?.open, isTrue);
    });
  });

  group('الجواب', () {
    setUp(() {
      ConnectionAlertSettings.current.value = const ConnectionAlertThresholds(signalDbm: -70, ccqPct: 60);
      VpnNow.reset();
    });
    tearDown(() {
      SubscriberVoiceCheck.debugProbe = null;
      SubscriberVoiceCheck.debugVpnRun = null;
      SubscriberVoiceCheck.debugLocalAllowed = null;
      SubscriberVoiceCheck.debugVpnAllowed = null;
      SubscriberVoiceCheck.debugIsOpen = null;
      VpnNow.reset();
      ConnectionAlertSettings.current.value = const ConnectionAlertThresholds();
    });

    test('غير متّصل أو منتهي أو مطفي ⇒ حاله وحده بلا فحص جهاز — وغير المتّصل بكلمة قسمه «غير متّصل الآن»', () async {
      var probed = 0;
      SubscriberVoiceCheck.debugProbe = (_) async {
        probed++;
        return null;
      };
      final off = SubscriberVoiceCheck(_sub('a', online: false));
      await off.run();
      // ١٠ نوفمبر: كان «فعّال وطافي» — والفحص العامّ يسمّيه «غير متّصل الآن»
      expect(off.headline, 'فعّال وغير متّصل الآن');
      expect(off.daysLine, 'باقي 20 يوماً');
      expect(off.deviceLine, isNull);
      final exp = SubscriberVoiceCheck(_sub('b', days: -3));
      await exp.run();
      expect(exp.headline, 'منتهي ومتّصل');
      expect(exp.daysLine, 'منتهي منذ 3 أيام');
      final dis = SubscriberVoiceCheck(_sub('c', enabled: false, online: false));
      await dis.run();
      expect(dis.headline, 'مطفي (معطّل)');
      expect(probed, 0, reason: 'لا يُقرأ جهاز من ليس متّصلاً وفعّالاً');
    });

    test('متّصلٌ وفعّال ⇒ جهازه من شبكتك: الإشارة وCCQ بحدود المدير', () async {
      SubscriberVoiceCheck.debugLocalAllowed = () => true;
      SubscriberVoiceCheck.debugProbe =
          (_) async => DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.7', ubnt: _ubnt(-78, 92));
      final c = SubscriberVoiceCheck(_sub('ali'));
      await c.run();
      expect(c.headline, 'فعّال ومتّصل');
      expect(c.row?.reading?.vpn, isFalse);
      expect(c.row?.reading?.ccq, 92);
      expect(c.row?.problems.map((x) => x.kind), [ConnectionProblemKind.signal]);
      expect(c.deviceLine, 'بمشكلة — ${c.row!.problems.map((x) => x.label).join(' · ')}',
          reason: 'قسمه «بمشكلة» ثمّ مشكلته بسطرها كـ«الفحص العامّ»');
      expect(c.phase, VoiceCheckPhase.done);

      SubscriberVoiceCheck.debugProbe =
          (_) async => DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.7', ubnt: _ubnt(-55, 95));
      final ok = SubscriberVoiceCheck(_sub('ok'));
      await ok.run();
      expect(ok.deviceLine, 'الإشارة، CCQ والكيبل سليمة');
    });

    test('لا يردّ من شبكتك ⇒ يُفحص عبر VPN شركته (ضوء الأولت كذلك)', () async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => true;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugProbe = (_) async => null;
      MergedCompany? ran;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {
        ran = c;
        VpnNow.debugApplyCompany(
            b.key,
            const VpnNowResult(ok: true, message: 'تم', readings: {
              'fiber.u': VpnSubReading(src: 'olt', rx: -29.5, temp: 44),
            }));
      };
      final c = SubscriberVoiceCheck(_sub('fiber.u', company: b.key), company: b);
      await c.run();
      expect(ran?.key, b.key, reason: 'فحص شركته وحدها');
      expect(c.row?.reading?.vpn, isTrue);
      expect(c.row?.reading?.via, 'الأولت');
      expect(c.row?.problems.single.kind, ConnectionProblemKind.fiberRx);
    });

    test('٩ نوفمبر: يردّ عبر الـVPN بلا مقاييس ⇒ «جهازه ما ردّ» بسببه لا «سليم»، وبلا فحصٍ ثانٍ', () async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      var runs = 0;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async => runs++;
      VpnNow.debugApplyCompany(
          b.key,
          const VpnNowResult(ok: true, message: 'تم', readings: {
            'auth.u': VpnSubReading(src: 'ping', ms: 9, err: 'login_failed'),
          }));
      final c = SubscriberVoiceCheck(_sub('auth.u', company: b.key), company: b);
      await c.run();
      expect(c.row, isNull);
      expect(c.deviceLine, 'جهازه ما ردّ — يردّ، ما انفتح برمزه المحفوظ');
      expect(c.cat, SubsCheckCat.noReply);
      expect(runs, 0, reason: 'آخر قراءةٍ تكفي — لا فحص VPN جديد');

      // ولا قراءة سابقة: الفحص الآن يُرجع البنك وحده ⇒ السطر نفسه (لا جوابٌ فارغ)
      VpnNow.reset();
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {
        runs++;
        VpnNow.debugApplyCompany(b.key, const VpnNowResult(ok: true, message: 'تم', readings: {'p.u': VpnSubReading(src: 'ping', ms: 5)}));
      };
      final p = SubscriberVoiceCheck(_sub('p.u', company: b.key), company: b);
      await p.run();
      expect(runs, 1);
      expect(p.row, isNull);
      expect(p.deviceLine, 'جهازه ما ردّ — يردّ، ما انقرت مقاييسه');
    });

    test('لا طريق ⇒ «لم يُفحص» بسببه (كان «بلا إدارة»)', () async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async => VpnNow.debugNote(b.key, '«ايرث لنك» تحتاج VPN');
      final c = SubscriberVoiceCheck(_sub('x', company: b.key), company: b);
      await c.run();
      expect(c.row, isNull);
      expect(c.deviceLine, 'لم يُفحص — «ايرث لنك» تحتاج VPN');
      expect(c.cat, SubsCheckCat.unchecked);
      VpnNow.debugNote(b.key, null);

      SubscriberVoiceCheck.debugVpnAllowed = () => false;
      final e = SubscriberVoiceCheck(_sub('y'));
      await e.run();
      expect(e.deviceLine, 'لم يُفحص — الفحص عبر VPN غير مفعّل لك');
    });

    // ١٠ نوفمبر: الجواب بأقسام «الفحص العامّ» وكلماتها — القسم نفسه الذي يضع فيه الفحص العامّ المشتركَ نفسه، والسبب بنصّ صفّه
    test('١٠ نوفمبر: الميّت عبر الـVPN «جهازه ما ردّ — لا يستجيب» كصفّه في الفحص العامّ', () async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async =>
          VpnNow.debugApplyCompany(b.key, const VpnNowResult(ok: true, message: 'تم', readings: {'d.u': VpnSubReading(src: 'dead')}));
      final s = _sub('d.u', company: b.key);
      final c = SubscriberVoiceCheck(s, company: b);
      await c.run();
      final r = SubscribersCheck.mixed([s], (_) => c.limits, peek: (_) => null, vpnWaits: (_) => false);
      final m = r.missing.single;
      expect(c.cat, SubscribersCheck.catOf(m.why));
      expect(c.deviceLine, '${SubsCheckCat.noReply.label} — ${SubscribersCheck.missText(m)}');
      expect(c.deviceLine, 'جهازه ما ردّ — لا يستجيب');
      expect(c.spoken, 'فعّال ومتّصل · باقي 20 يوماً · جهازه ما ردّ — لا يستجيب');
    });

    test('١٠ نوفمبر: ما ردّ من شبكتك (بلا VPN لك، أو والخادم لم يقرأه) · ردّ بلا مقاييس · الخادم لم يسأله أو تعذّر الفحص ⇒ «لم يُفحص»', () async {
      SubscriberVoiceCheck.debugLocalAllowed = () => true;
      SubscriberVoiceCheck.debugVpnAllowed = () => false;
      SubscriberVoiceCheck.debugProbe = (_) async => null;
      final a = SubscriberVoiceCheck(_sub('a'));
      await a.run();
      expect([a.cat, a.deviceLine], [SubsCheckCat.noReply, 'جهازه ما ردّ — من شبكتك']);

      // جهازٌ ردّ بلا مقاييس (ليس نانو ولا ضوئيّاً) ⇒ «بلا مقاييس» لا «ما ردّ»
      SubscriberVoiceCheck.debugProbe = (_) async => const DeviceHealthSnapshot(kind: DeviceKind.other, ip: '10.0.0.7');
      final n = SubscriberVoiceCheck(_sub('n'));
      await n.run();
      expect([n.cat, n.deviceLine], [SubsCheckCat.noMetrics, 'بلا مقاييس — جهازه ليس نانو ولا وحدةً ضوئيّة']);

      // فحص الخادم اكتمل ولا قراءة له
      SubscriberVoiceCheck.debugProbe = (_) async => null;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async =>
          VpnNow.debugApply(VpnNowKind.subscribers, const VpnNowResult(ok: true, message: 'تم', readings: {'other': VpnSubReading(src: 'dead')}));
      final v = SubscriberVoiceCheck(_sub('v'));
      await v.run();
      expect([v.cat, v.deviceLine], [SubsCheckCat.noReply, 'جهازه ما ردّ — من شبكتك'],
          reason: 'سُئل من شبكتك وما ردّ؛ والخادم لم يسأله فلا يُقال «ولا عبر VPN»');

      // خارج شبكتك (لا فحص من الهاتف) والخادم اكتمل بلا قراءةٍ له ⇒ لم يُسأل جهازه ⇒ «لم يُفحص» لا «ما ردّ»
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      final w = SubscriberVoiceCheck(_sub('w'));
      await w.run();
      expect([w.cat, w.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص — لم يُقرأ عبر VPN']);
      SubscriberVoiceCheck.debugLocalAllowed = () => true;

      // «كل الشركات»: مشترك شركةٍ غير المفتوحة طريقها VPN شركتها — فشل الهاتف معه ليس «ما ردّ من شبكتك»
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugIsOpen = (c) async => c.key != b.key;
      // فحص شركته عبر الـVPN اكتمل بلا قراءةٍ له — قراءاتها بمكانها لا بقراءات المفتوحة (المراجعة: «لم يُقرأ عبر VPN»
      // لفحصٍ مكتملٍ لشركته وحده)
      SubscriberVoiceCheck.debugVpnRun = (s, c) async => VpnNow.debugApplyCompany(
          b.key, const VpnNowResult(ok: true, message: 'تم', readings: {'other': VpnSubReading(src: 'dead')}));
      final o = SubscriberVoiceCheck(_sub('o', company: b.key), company: b);
      await o.run();
      expect([o.cat, o.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص — لم يُقرأ عبر VPN']);
      // والمفتوحة نفسها تُقرأ من شبكتك ⇒ فشلها «ما ردّ»
      SubscriberVoiceCheck.debugIsOpen = (_) async => true;
      final p = SubscriberVoiceCheck(_sub('p', company: b.key), company: b);
      await p.run();
      expect([p.cat, p.deviceLine], [SubsCheckCat.noReply, 'جهازه ما ردّ — من شبكتك']);
      SubscriberVoiceCheck.debugIsOpen = null;

      // الفحص عبر الـVPN تعذّر ⇒ لم يُفحص بسببه (لا «ما ردّ» كاذبة)
      VpnNow.reset();
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {
        VpnNow.subscribers
          ..phase = VpnBarPhase.failed
          ..line = 'الـVPN ما اتّصل الآن — حاول بعد قليل';
      };
      final f = SubscriberVoiceCheck(_sub('f'));
      await f.run();
      expect([f.cat, f.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص — الـVPN ما اتّصل الآن — حاول بعد قليل']);
    });
  });
  // ───────────── المراجعة ١٠ نوفمبر (إصدار 180): فحص الـVPN لم يكتمل، وعمر قراءته ─────────────
  // الجواب بكلمات «الفحص العامّ» وقسمه في اللحظة نفسها: الفحص لم يبلغه ⇒ «لم يُفحص بعد» لا «جهازه ما ردّ»؛ ولا يبدأ
  // فحصاً لم يطلبه أحد بعد ظهور الجواب؛ وقراءة الـVPN القديمة (حتى ٣٠ د) بعمرها لا كأنّها الآن.
  group('المراجعة ١٠ نوفمبر — فحص الـVPN لم يكتمل وعمر قراءته', () {
    const kE = 'c0000000000e1';
    const kX = 'c0000000000f1';
    setUp(() {
      ConnectionAlertSettings.current.value = const ConnectionAlertThresholds(signalDbm: -70, ccqPct: 60);
      VpnNow.reset();
    });
    tearDown(() {
      SubscriberVoiceCheck.debugProbe = null;
      SubscriberVoiceCheck.debugVpnRun = null;
      SubscriberVoiceCheck.debugLocalAllowed = null;
      SubscriberVoiceCheck.debugVpnAllowed = null;
      SubscriberVoiceCheck.debugIsOpen = null;
      VpnNow.reset();
      ConnectionAlertSettings.current.value = const ConnectionAlertThresholds();
    });

    /// الفحص الجاري يمضي لما بعد شركته أو ينتهي — ويُبلغ مستمعيه.
    void finish(VpnNowJob job) {
      job
        ..phase = VpnBarPhase.done
        ..queue = const []
        ..current = null;
      job.clear();
    }

    test(
        '«كل الشركات»: فحص شركته عبر الـVPN بالدور حين انتهت المهلة ⇒ «لم يُفحص بعد — بانتظار الفحص» لا «جهازه ما '
        'ردّ»، كصفّه في «الفحص العامّ» — ثمّ يتحدّث وحده حين يكتمل', () async {
      final a = _co('c0000000000a1', 'سوبرنت');
      SubscriberVoiceCheck.debugLocalAllowed = () => true;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugIsOpen = (_) async => true; // المفتوحة: الهاتف على شبكتها وما ردّ جهازه
      SubscriberVoiceCheck.debugProbe = (_) async => null;
      // «الفحص العامّ» يفحص شركاته عبر الـVPN والمفتوحة آخرها (تكملة الفايبر) — والمهلة انتهت وشركته بالدور
      SubscriberVoiceCheck.debugVpnRun = (s, c) async => VpnNow.subscribers
        ..phase = VpnBarPhase.running
        ..queue = [kE, a.key]
        ..current = kE;
      final c = SubscriberVoiceCheck(_sub('w', company: a.key), company: a);
      var told = 0;
      c.addListener(() => told++);
      await c.run();
      expect([c.cat, c.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص بعد — بانتظار الفحص']);
      expect(c.spoken, isNot(contains('ما ردّ')), reason: 'كان «جهازه ما ردّ — من شبكتك» والفحص لم يبلغه');
      // «الفحص العامّ» في اللحظة نفسها: القسم والسبب نفسهما
      final m = SubscribersCheck.mixed([c.sub], (_) => c.limits,
          peek: (_) => (snap: null, stale: false, at: DateTime.now()), localFailsFor: (k) => k == a.key).missing.single;
      expect([SubscribersCheck.catOf(m.why), SubscribersCheck.missText(m, running: true)], [c.cat, c.note]);

      // دور شركته يكتمل بقراءةٍ له ⇒ الجواب منها (بلا فحصٍ جديد)
      final before = told;
      VpnNow.debugApplyCompany(a.key,
          const VpnNowResult(ok: true, message: 'تم', readings: {'w': VpnSubReading(src: 'olt', rx: -21.5, temp: 41)}));
      finish(VpnNow.subscribers);
      expect(told, greaterThan(before), reason: 'الجواب يتحدّث وحده');
      expect([c.row?.reading?.vpn, c.deviceLine], [true, 'الضوء سليمة']);
      c.dispose();
    });

    test('الهاتف لم يسأل جهازه («وضع VPN» عند البدء) ⇒ لا «ما ردّ من شبكتك» ولو رجع لشبكته أثناء انتظار الـVPN',
        () async {
      var onNet = false;
      var probes = 0;
      SubscriberVoiceCheck.debugLocalAllowed = () => onNet;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugProbe = (_) async {
        probes++;
        return null;
      };
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {
        VpnNow.debugApply(VpnNowKind.subscribers,
            const VpnNowResult(ok: true, message: 'تم', readings: {'other': VpnSubReading(src: 'dead')}));
        onNet = true; // الحارس أطفأ «وضع VPN» والفحص جارٍ
      };
      final c = SubscriberVoiceCheck(_sub('m'));
      await c.run();
      expect(probes, 0);
      expect([c.cat, c.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص — لم يُقرأ عبر VPN'],
          reason: 'فحص الخادم اكتمل ولم يسأل جهازه، والهاتف لم يسأله');
    });

    test('الفحص أُلغي قبل أن يكتمل لشركته («وضع VPN» انطفأ) ⇒ «لم يُفحص بعد عبر VPN» لا «لم يُقرأ عبر VPN»', () async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {
        VpnNow.subscribers
          ..phase = VpnBarPhase.running
          ..queue = [b.key]
          ..current = b.key;
        VpnNow.subscribers.cancel(); // exitMode
      };
      final c = SubscriberVoiceCheck(_sub('x', company: b.key), company: b);
      await c.run();
      expect([c.cat, c.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص بعد عبر VPN']);
    });

    testWidgets('المهلة وفحصٌ جارٍ لغير شركته ⇒ «لم يُفحص» بسببه، ولا يبدأ فحصاً بعد ظهور الجواب', (t) async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      final job = VpnNow.subscribers
        ..phase = VpnBarPhase.running
        ..queue = [kX]
        ..current = kX;
      final c = SubscriberVoiceCheck(_sub('y', company: b.key), company: b);
      final run = c.run();
      await t.pump(SubscriberVoiceCheck.vpnTimeout + const Duration(seconds: 1));
      await run;
      expect([c.cat, c.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص بعد عبر VPN']);
      finish(job);
      await t.pump();
      expect(job.busy, isFalse, reason: 'كان يبدأ فحص «ايرث لنك» بعد ظهور الجواب ولم يطلبه أحد');
      c.dispose();
    });

    testWidgets('أُغلق الجواب وهو ينتظر فحصاً جارياً ⇒ لا يبدأ فحصاً بعده', (t) async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      final job = VpnNow.subscribers
        ..phase = VpnBarPhase.running
        ..queue = [kX]
        ..current = kX;
      final c = SubscriberVoiceCheck(_sub('y', company: b.key), company: b);
      unawaited(c.run());
      await t.pump(const Duration(seconds: 5));
      expect(c.phase, VoiceCheckPhase.vpn);
      c.dispose();
      await t.pump();
      finish(job);
      await t.pump(const Duration(seconds: 1));
      expect(job.busy, isFalse);
    });

    testWidgets('«كل الشركات»: شركته فُحصت في الفحص الجاري نفسه ⇒ الجواب فوراً من نتيجته، بلا انتظار الباقي ولا فحصٍ',
        (t) async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      VpnNow.debugApplyCompany(
          b.key, const VpnNowResult(ok: true, message: 'تم', readings: {'other': VpnSubReading(src: 'dead')}));
      final job = VpnNow.subscribers
        ..phase = VpnBarPhase.running
        ..queue = [b.key, kX]
        ..current = kX;
      final c = SubscriberVoiceCheck(_sub('z', company: b.key), company: b);
      final run = c.run();
      await t.pump(const Duration(milliseconds: 50));
      expect(c.phase, VoiceCheckPhase.done, reason: 'لا ينتظر الشركات بعد شركته');
      await run;
      expect([c.cat, c.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص — لم يُقرأ عبر VPN']);
      finish(job);
      await t.pump();
      expect(job.busy, isFalse, reason: 'لا فحصٌ ثانٍ لشركةٍ فُحصت للتوّ');
      c.dispose();
    });

    test('جوابٌ من آخر قراءةٍ عبر الـVPN ليست من هذه اللحظة ⇒ بعمرها بكلمات «الفحص العامّ»، والجديدة بلا عمر',
        () async {
      addTearDown(() => SubscriberVoiceCheck.debugNow = null);
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      var runs = 0;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async => runs++;
      VpnNow.debugApplyCompany(
          b.key,
          const VpnNowResult(ok: true, message: 'تم', readings: {
            'old.u': VpnSubReading(src: 'cpe', sig: -55, ccq: 95, lan: '100'),
            'ping.u': VpnSubReading(src: 'ping', ms: 7),
          }));
      final c = SubscriberVoiceCheck(_sub('old.u', company: b.key), company: b);
      await c.run();
      expect(runs, 0, reason: 'آخر قراءةٍ تكفي (السرعة أوّلاً) — بعمرها');
      expect(c.vpnAge, isNull, reason: 'من هذه الدقيقة');
      expect(c.spoken, 'فعّال ومتّصل · باقي 20 يوماً · الإشارة، CCQ والكيبل سليمة');
      // بعد ١٢ دقيقة: القراءة نفسها (آخر فحصٍ عبر الـVPN حتى ٣٠ د) بعمرها
      SubscriberVoiceCheck.debugNow = () => DateTime.now().add(const Duration(minutes: 12));
      expect(c.vpnAge, 'منذ 12 دقيقة');
      expect(c.spoken, 'فعّال ومتّصل · باقي 20 يوماً · الإشارة، CCQ والكيبل سليمة · عبر VPN الشركة · منذ 12 دقيقة');
      // يردّ بلا مقاييس من القراءة نفسها ⇒ بعمرها كذلك
      final p = SubscriberVoiceCheck(_sub('ping.u', company: b.key), company: b);
      await p.run();
      expect(p.spoken, endsWith('جهازه ما ردّ — يردّ، ما انقرت مقاييسه · عبر VPN الشركة · منذ 12 دقيقة'));
      // وفحص الهاتف الطازج بلا عمر
      SubscriberVoiceCheck.debugLocalAllowed = () => true;
      SubscriberVoiceCheck.debugProbe =
          (_) async => DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.7', ubnt: _ubnt(-55, 95));
      final l = SubscriberVoiceCheck(_sub('l'));
      await l.run();
      expect([l.row?.reading?.vpn, l.vpnAge], [false, null]);
    });

    // المراجعة الثانية: آخر فحصٍ لايرث لنك (دون ٣٠ د) قرأه ميّتاً، و«الفحص العامّ» يعيد فحصها الآن ودورها بعد
    // شركةٍ أخرى
    testWidgets(
        'المراجعة الثانية: آخر قراءته «لا يستجيب» وشركته بالدور حين انتهت المهلة ⇒ الجواب منها كصفّه الآن، ثمّ من '
        'نتيجة دورها حين يكتمل', (t) async {
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      VpnNow.debugApplyCompany(
          b.key, const VpnNowResult(ok: true, message: 'تم', readings: {'d.u': VpnSubReading(src: 'dead')}));
      final job = VpnNow.subscribers
        ..phase = VpnBarPhase.running
        ..queue = [kX, b.key]
        ..current = kX;
      final s = _sub('d.u', company: b.key);
      final c = SubscriberVoiceCheck(s, company: b);
      // «الفحص العامّ» في اللحظة نفسها (الهاتف لا يشهد على جهاز ايرث لنك)
      SubsCheckReport screen() =>
          SubscribersCheck.mixed([s], (_) => c.limits, peek: (_) => null, localFailsFor: (_) => false);
      var told = 0;
      c.addListener(() => told++);
      final run = c.run();
      await t.pump(SubscriberVoiceCheck.vpnTimeout + const Duration(seconds: 1));
      await run;
      final m = screen().missing.single;
      expect([c.cat, c.deviceLine], [SubscribersCheck.catOf(m.why), 'جهازه ما ردّ — ${SubscribersCheck.missText(m)}']);
      expect(c.deviceLine, 'جهازه ما ردّ — لا يستجيب');
      // دورها يكتمل وقرأه سليماً ⇒ الجواب يتحدّث وحده كصفّه (كان يبقى «جهازه ما ردّ»)
      final before = told;
      VpnNow.debugApplyCompany(
          b.key,
          const VpnNowResult(ok: true, message: 'تم', readings: {
            'd.u': VpnSubReading(src: 'cpe', sig: -55, ccq: 95, lan: '100'),
          }));
      finish(job);
      await t.pump();
      expect(screen().healthy.single.sub.username, 'd.u');
      expect(told, greaterThan(before), reason: 'الجواب يتحدّث وحده');
      expect([c.cat, c.row?.reading?.vpn, c.deviceLine], [null, true, 'الإشارة، CCQ والكيبل سليمة']);
      expect(job.busy, isFalse, reason: 'بلا فحصٍ جديد');
      c.dispose();
    });

    test(
        'المراجعة الثانية: شركته طريقها VPN ولم يكتمل لها فحص ⇒ سببٌ واحد «لم يُفحص بعد عبر VPN» — في الجواب وصفّه '
        'والتقرير المنسوخ، ولو كانت موجة الهاتف جارية', () async {
      final a = _co('c0000000000a1', 'سوبرنت');
      final b = _co('c0000000000b1', 'ايرث لنك');
      SubscriberVoiceCheck.debugLocalAllowed = () => true;
      SubscriberVoiceCheck.debugVpnAllowed = () => true;
      SubscriberVoiceCheck.debugIsOpen = (c) async => c.key == a.key; // الهاتف على شبكة سوبرنت
      SubscriberVoiceCheck.debugProbe = (_) async => null;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {
        VpnNow.subscribers
          ..phase = VpnBarPhase.running
          ..queue = [b.key]
          ..current = b.key;
        VpnNow.subscribers.cancel(); // «وضع VPN» انطفأ قبل أن يكتمل دورها
      };
      final s = _sub('e.u', company: b.key);
      final c = SubscriberVoiceCheck(s, company: b);
      await c.run();
      expect([c.cat, c.deviceLine], [SubsCheckCat.unchecked, 'لم يُفحص بعد عبر VPN'],
          reason: 'لا «لم يُفحص — لم يُفحص…»');
      expect(c.spoken, 'فعّال ومتّصل · باقي 20 يوماً · لم يُفحص بعد عبر VPN');
      // «الفحص العامّ» في اللحظة نفسها كما تمرّره الشاشة (المفتوحة وحدها تُقرأ من شبكتك): موجة الهاتف جاريةٌ ولم تبلغه،
      // ثمّ انتهت وما ردّ لها
      final now = DateTime.now();
      final wave = SubsWave.idle.start([SubsWave.keyOf(b.key, 'e.u')], now);
      for (final (w, p) in [
        (wave, (snap: null, stale: true, at: now.subtract(const Duration(minutes: 6)))),
        (wave.finish(now), (snap: null, stale: false, at: now)),
      ]) {
        final r =
            SubscribersCheck.mixed([s], (_) => c.limits, peek: (_) => p, wave: w, localFailsFor: (k) => k == a.key);
        final m = r.missing.single;
        expect([SubscribersCheck.catOf(m.why), SubscribersCheck.missText(m, running: w.running)], [c.cat, c.deviceLine],
            reason: w.running ? 'كان «بانتظار الفحص»' : 'كان «لم يصله الفحص»');
        expect(SubscribersCheck.reportText(r, progress: SubscribersCheck.progress(subs: 1, wave: w, at: now)),
            contains('• e.u (e.u) — لم يُفحص بعد عبر VPN'));
      }
      // وصفحةٌ واحدة عبر الـVPN بلا فحصٍ مكتمل — السبب نفسه في صفّه وجوابه
      SubscriberVoiceCheck.debugLocalAllowed = () => false;
      SubscriberVoiceCheck.debugVpnRun = (s, c) async {};
      final one = SubscriberVoiceCheck(_sub('v.u'));
      await one.run();
      final v =
          SubscribersCheck.vpn([one.sub], (_) => one.limits, reading: (_) => null, readAt: (_) => null, running: false);
      expect([one.deviceLine, SubscribersCheck.missText(v.missing.single)],
          ['لم يُفحص بعد عبر VPN', 'لم يُفحص بعد عبر VPN']);
    });
  });
}
