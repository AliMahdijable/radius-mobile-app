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
}
