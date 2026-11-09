import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';
import 'package:rad_mysvcs/services/vpn_now.dart' show VpnNowJob, VpnBarPhase;

/// «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك: «أ» و«فحص المشتركين ثكيل كلش»): من قراءات الكارتات نفسها وبحدود «تنبيه المشترك»
/// — المقروء يُعدّ، والمشكلة بنوعها (الكيبل أوّلاً)، والصفر ليس قراءة؛ وعبر الـVPN بالحدود نفسها.
Subscriber _sub(String u, {String? company, bool online = true, String? ip}) => Subscriber.fromJson({
      'username': u,
      'firstname': u,
      'lastname': '',
      'online_status': online ? 1 : 0,
      if (ip != null) 'ip': ip,
    }).withCompany(company);

UbiquitiStatus _ubnt(int sig, int ccq, {List<LanPort> lan = const [], String host = 'h'}) => UbiquitiStatus(
    hostname: host, firmware: 'XC.v8', uptimeSeconds: 100, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
    ccqPercent: ccq, distanceMeters: 300, txRateKbps: 100000, rxRateKbps: 100000, lanPorts: lan, peerMac: null,
    peerCount: 1, baseUrl: 'http://x');

void main() {
  const t = ConnectionAlertThresholds(signalDbm: -70, ccqPct: 70, fiberRxDbm: -25, fiberTempC: 70);
  ConnectionAlertThresholds limits(String? _) => t;

  test('من قراءات الهاتف: المقروء، والمشاكل بحدود المدير، والأسوأ أوّلاً', () {
    final subs = [_sub('a'), _sub('b'), _sub('c'), _sub('d'), _sub('e')];
    UbiquitiStatus ubnt(int sig, int ccq) => UbiquitiStatus(
          hostname: 'h', firmware: 'XC.v8', uptimeSeconds: 100, ssid: 's', mode: 'sta', signalDbm: sig, noiseFloorDbm: -95,
          ccqPercent: ccq, distanceMeters: 300, txRateKbps: 100000, rxRateKbps: 100000, lanPorts: const [], peerMac: null,
          peerCount: 1, baseUrl: 'http://x');
    final snaps = <String, DeviceHealthSnapshot>{
      'a': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.1', ubnt: ubnt(-78, 95)),
      'b': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.2', ubnt: ubnt(-55, 60)),
      'c': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '10.0.0.3', ubnt: ubnt(-50, 99)),
      'd': const DeviceHealthSnapshot(
          kind: DeviceKind.ont,
          ip: '10.0.0.4',
          ont: OntOpticalInfo(txPower: '2.1', rxPower: '-27.5', voltage: '3.3', temperature: '45', bias: '10', sendStatus: 'ok')),
    };
    final r = SubscribersCheck.local(subs, limits,
        peek: (s) => snaps[s.username] == null ? null : (snap: snaps[s.username], stale: false, at: DateTime(2026, 11, 8)));
    expect([r.total, r.read, r.unread], [5, 4, 1], reason: 'e بلا قراءة');
    expect(r.rows.map((x) => x.sub.username).toSet(), {'a', 'b', 'd'}, reason: 'c سليم');
    expect(r.of(ConnectionProblemKind.signal).single.sub.username, 'a');
    expect(r.of(ConnectionProblemKind.ccq).single.sub.username, 'b');
    expect(r.of(ConnectionProblemKind.fiberRx).single.sub.username, 'd');
  });

  test('عبر الـVPN: الكيبل والإشارة وCCQ والضوء بالحدود نفسها؛ الصفر والميّت ليسا قراءة', () {
    final subs = [_sub('a', company: 'k1'), _sub('b', company: 'k2'), _sub('c'), _sub('d'), _sub('e')];
    final reads = <String, VpnSubReading>{
      'a': const VpnSubReading(src: 'vpn', sig: -75, ccq: 0, lan: 'unplugged'),
      'b': const VpnSubReading(src: 'vpn', sig: 0, ccq: 50),
      'c': const VpnSubReading(src: 'vpn', rx: -26.0, temp: 72),
      'd': const VpnSubReading(src: 'dead'),
    };
    final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username]);
    expect([r.total, r.read], [5, 3], reason: 'd ميّت وe بلا قراءة');
    expect(r.rows.first.sub.username, 'a', reason: 'الكيبل أوّلاً');
    expect(r.rows.first.problems.map((p) => p.kind).toList(), [ConnectionProblemKind.cable, ConnectionProblemKind.signal],
        reason: 'CCQ صفرٌ ليس قراءة');
    expect(r.of(ConnectionProblemKind.ccq).single.sub.username, 'b', reason: 'إشارة صفرٌ لا تُعدّ ضعيفة');
    expect(r.of(ConnectionProblemKind.fiberRx).single.sub.username, 'c');
    expect(r.of(ConnectionProblemKind.fiberTemp).single.sub.username, 'c');
  });
  test('القراءة كاملةً لكلّ مقروء (المالك: «اظهار معلومات ال ccq كذلك») — والسليم الأقرب للحدّ أوّلاً', () {
    // ١٠ نوفمبر: «ما ردّ» لمن فُحص وما ردّ (f) — ومن لم يُفحص أصلاً «لم يُفحص» (h بعنوانه، i بلا عنوان) لا «ما ردّ»
    final subs = [
      _sub('a'), _sub('b'), _sub('c'), _sub('d'), _sub('e', online: false), _sub('f'), _sub('g'), //
      _sub('h', ip: '10.0.0.8'), _sub('i'),
    ];
    final at = DateTime(2026, 11, 8, 4);
    final snaps = <String, DeviceHealthSnapshot>{
      // سليم بعيدٌ عن الحدّ (-70): -50 ⇒ هامش 20
      'a': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: _ubnt(-50, 95, host: 'Nano-A',
          lan: const [LanPort(name: 'eth0', speed: '100Mbps-Full', plugged: true)])),
      // سليم قريب: -67 ⇒ هامش 3
      'b': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '2', ubnt: _ubnt(-67, 90,
          lan: const [LanPort(name: 'eth0', speed: null, plugged: true)])),
      // كيبل مفصول
      'c': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '3', ubnt: _ubnt(-60, 95,
          lan: const [LanPort(name: 'eth0', speed: null, plugged: false)])),
      'd': const DeviceHealthSnapshot(
          kind: DeviceKind.ont,
          ip: '4',
          ont: OntOpticalInfo(txPower: '2.1', rxPower: '-20.5', voltage: '3.3', temperature: '41', bias: '10', sendStatus: 'ok', model: 'MH80', vendor: 'zte')),
      // جهازٌ بلا مقاييس
      'g': const DeviceHealthSnapshot(kind: DeviceKind.other, ip: '7'),
    };
    final r = SubscribersCheck.local(subs, limits,
        peek: (s) => s.username == 'f'
            ? (snap: null, stale: false, at: at) // فُحص وما ردّ
            : snaps[s.username] == null
                ? null
                : (snap: snaps[s.username], stale: false, at: at));
    expect(r.healthy.map((x) => x.sub.username).toList(), ['b', 'd', 'a'],
        reason: 'b هامشه 3 · d الضوء ‎-20.5 وحدّه ‎-25 ⇒ 4.5 · a هامشه 20');
    final a = r.healthy.last.reading!;
    expect([a.sig, a.ccq, a.lan, a.device, a.at], [-50, 95, '100', 'Nano-A', at]);
    expect(r.healthy.first.reading!.lan, 'on', reason: 'موصولٌ بسرعةٍ لا تُعرف ليس مفصولاً');
    final d = r.healthy[1].reading!;
    expect([d.rx, d.temp, d.device], [-20.5, 41.0, 'MH80']);
    expect(r.rows.single.sub.username, 'c');
    expect(r.rows.single.reading!.lan, 'unplugged');
    expect({for (final m in r.missing) m.sub.username: m.why}, {
      'e': SubsMissWhy.offline,
      'f': SubsMissWhy.noReply,
      'g': SubsMissWhy.noMetrics,
      'h': SubsMissWhy.unchecked,
      'i': SubsMissWhy.unchecked,
    });
    expect({for (final m in r.missing) m.sub.username: m.note}['i'], 'بلا عنوان IP');
    expect([r.total, r.read, r.unread], [9, 4, 5]);
  });

  test('داخل النوع الواحد: الأشدّ أوّلاً — والـVPN: من السكتر/الأولت، والبنك وحده، والميّت «لا يستجيب»', () {
    final subs = [_sub('w1'), _sub('w2'), _sub('w3'), _sub('p'), _sub('x'), _sub('o', online: false)];
    final reads = <String, VpnSubReading>{
      'w1': const VpnSubReading(src: 'cpe', sig: -74, ccq: 90, lan: '100'),
      'w2': const VpnSubReading(src: 'sector', sig: -82, ccq: 85),
      'w3': const VpnSubReading(src: 'olt', rx: -24.0, temp: 50),
      'p': const VpnSubReading(src: 'ping', ms: 12),
      'x': const VpnSubReading(src: 'dead'),
    };
    final when = DateTime(2026, 11, 8, 5);
    final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username], readAt: (_) => when);
    expect(r.rows.map((x) => x.sub.username).toList(), ['w2', 'w1'], reason: '‎-82 قبل ‎-74');
    expect(r.rows.first.reading!.via, 'السكتر');
    expect(r.rows.first.reading!.at, when);
    // ٩ نوفمبر: البنك وحده (يردّ بلا مقاييس) «لم يُقرأ» لا «سليم» — كان هنا آخر «سليم»
    expect(r.healthy.map((x) => x.sub.username).toList(), ['w3']);
    expect(r.healthy.first.reading!.via, 'الأولت');
    expect([for (final m in r.missing) m.why], [SubsMissWhy.dead, SubsMissWhy.unmeasured, SubsMissWhy.offline],
        reason: 'الميّت أوّلاً ثمّ من يردّ بلا مقاييس');
    expect(r.missing[1].sub.username, 'p');
    expect(r.missing[1].note, 'يردّ، ما انقرت مقاييسه');
    expect([r.total, r.read], [6, 3]);
  });

  group('٩ نوفمبر — «فحص المشتركين» عبر الـVPN: من يردّ ولم تُقرأ مقاييسه ليس «سليم»', () {
    test('🚨 ضغطة نفق الشركة: يردّ 156 وقُرئ 0 (رُفض الدخول 153) ⇒ لا أحد «سليم» — كلّهم «لم يُقرأ» بسببهم', () {
      // من فحص الخادم كما يُرجعه اليوم (src: ping بلا مقاييس)، وخادمٌ لاحق يضيف err
      final subs = [for (var i = 0; i < 156; i++) _sub('u$i')];
      final reads = <String, VpnSubReading>{
        for (var i = 0; i < 156; i++)
          'u$i': VpnSubReading.fromJson({'u': 'u$i', 'src': 'ping', 'ms': 20 + i % 5, if (i < 153) 'err': 'login_failed'})!,
      };
      final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username]);
      expect(r.healthy, isEmpty);
      expect(r.rows, isEmpty);
      expect([r.read, r.unread], [0, 156]);
      expect(r.missing.every((m) => m.why == SubsMissWhy.unmeasured), isTrue);
      expect(r.missing.where((m) => m.note == 'يردّ، ما انفتح برمزه المحفوظ').length, 153);
      expect(r.missing.where((m) => m.note == 'يردّ، ما انقرت مقاييسه').length, 3, reason: 'خادمٌ بلا err ⇒ السطر العامّ');
    });

    test('الأسباب من الخادم إن أعطاها، والحقل اختياريّ؛ وجهازٌ قُرئ بلا أرقام «بلا قياسات»', () {
      expect(VpnSubReading.fromJson({'src': 'ping', 'ms': 4})!.err, isNull);
      expect(VpnSubReading.fromJson({'src': 'ping', 'err': 'no_web'})!.err, 'no_web');
      expect(SubscribersCheck.unmeasuredLabel(const VpnSubReading(src: 'ping', err: 'no_web')), 'يردّ، واجهة إدارته ما تفتح');
      expect(const VpnSubReading(src: 'ping', ms: 4).measured, isFalse);
      expect(const VpnSubReading(src: 'cpe', sig: -60).measured, isTrue);
      expect(const VpnSubReading(src: 'cpe', lan: 'ok').measured, isTrue);
      expect(const VpnSubReading(src: 'cpe', sig: 0, ccq: 0).measured, isFalse, reason: 'الصفر ليس قراءة');
      final r = SubscribersCheck.vpn([_sub('c')], limits, reading: (_) => const VpnSubReading(src: 'cpe'));
      expect(r.missing.single.why, SubsMissWhy.noMetrics);
    });

    test('«كل الشركات»: البنك وحده لا يغلب قراءة الهاتف الحقيقيّة ولو أحدث؛ وبلا قراءة هاتف ⇒ «لم يُقرأ» لا «سليم»', () {
      final phoneAt = DateTime(2026, 11, 9, 10, 0);
      final vpnAt = DateTime(2026, 11, 9, 10, 5);
      final subs = [_sub('both', company: 'kE'), _sub('ping', company: 'kE')];
      final r = SubscribersCheck.mixed(
        subs,
        limits,
        peek: (s) => s.username == 'both'
            ? (snap: DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '3', ubnt: _ubnt(-50, 95)), stale: false, at: phoneAt)
            : null,
        reading: (s) => const VpnSubReading(src: 'ping', ms: 9, err: 'login_failed'),
        readAt: (_) => vpnAt,
      );
      expect(r.healthy.single.sub.username, 'both');
      expect(r.healthy.single.reading!.vpn, isFalse, reason: 'قراءة الهاتف بمقاييسها');
      expect(r.missing.single.sub.username, 'ping');
      expect(r.missing.single.why, SubsMissWhy.unmeasured);
      expect(r.missing.single.note, 'يردّ، ما انفتح برمزه المحفوظ');
    });
  });
  test('«كل الشركات»: كلّ مشتركٍ بأحدث قراءته — الهاتف لشركةٍ والـVPN لأخرى، ومن لم يُقرأ وشركته لم تُفحص يُقال سببها', () {
    // المالك ٨ نوفمبر: «مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم… ايرث لنك رابطلها vpn والسوبرنت تشتغل لوكل»
    final subs = [
      _sub('s1', company: 'kS'), _sub('s2', company: 'kS'), // سوبرنت — من الهاتف
      _sub('e1', company: 'kE'), _sub('e2', company: 'kE'), // ايرث لنك — عبر VPN
      _sub('x1', company: 'kX'), // شركةٌ ثالثة بلا VPN
      _sub('both', company: 'kE'), // الاثنان: الأحدث يغلب
    ];
    final phoneAt = DateTime(2026, 11, 8, 10, 0);
    final vpnAt = DateTime(2026, 11, 8, 10, 5);
    final snaps = <String, DeviceHealthSnapshot>{
      's1': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '1', ubnt: _ubnt(-80, 95)),
      's2': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '2', ubnt: _ubnt(-50, 95)),
      'both': DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: '3', ubnt: _ubnt(-50, 95)),
    };
    final reads = <String, VpnSubReading>{
      'e1': const VpnSubReading(src: 'cpe', sig: -55, ccq: 40, lan: '100'),
      'e2': const VpnSubReading(src: 'dead'),
      'both': const VpnSubReading(src: 'cpe', sig: -85, ccq: 90),
    };
    final r = SubscribersCheck.mixed(
      subs,
      limits,
      peek: (s) => snaps[s.username] == null ? null : (snap: snaps[s.username], stale: false, at: phoneAt),
      reading: (s) => reads[s.username],
      readAt: (c) => c == 'kE' ? vpnAt : null,
      companyNote: (c) => c == 'kX' ? '«ثالثة» تحتاج VPN' : null,
    );
    expect([r.total, r.read], [6, 4]);
    expect({for (final x in r.rows) x.sub.username}, {'s1', 'e1', 'both'});
    expect(r.rows.firstWhere((x) => x.sub.username == 'both').reading!.sig, -85,
        reason: 'قراءة الـVPN (10:05) أحدث من الهاتف (10:00)');
    expect(r.rows.firstWhere((x) => x.sub.username == 'e1').reading!.at, vpnAt);
    expect(r.healthy.single.sub.username, 's2');
    final miss = {for (final m in r.missing) m.sub.username: (m.why, m.note)};
    expect(miss['e2'], (SubsMissWhy.dead, null));
    expect(miss['x1'], (SubsMissWhy.company, '«ثالثة» تحتاج VPN'));
  });

  // ───────────── ١٠ نوفمبر: العدّاد يعدّ الفحص، والأقسام بمعناها ─────────────
  // المالك مع صورة «قُرئ 58 من 113» (51%) و«لم يُقرأ 55»: «شنو علاقة العداد بالعدد مفروض العداد يمثل الفحص هيج راح يبرك
  // الوكيل» — «لم يُقرأ» كانت تخلط من ما ردّ جهازه بغير المتّصل، والشريط بعد الموجة يبقى 51% أبداً.
  group('١٠ نوفمبر — الأقسام', () {
    final at = DateTime(2026, 11, 10, 9);
    DeviceHealthSnapshot ok(String ip) => DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: ip, ubnt: _ubnt(-50, 95));

    test('غير المتّصل قسمه وحده «غير متّصل الآن» — لا داخل «جهازه ما ردّ»، بالطرق الثلاثة', () {
      final subs = [_sub('on.dead', ip: '1'), _sub('off.dead', online: false, ip: '2'), _sub('off.none', online: false)];
      // من الهاتف: فُحص الاثنان وما ردّا
      final l = SubscribersCheck.local(subs, limits,
          peek: (s) => s.username == 'off.none' ? null : (snap: null, stale: false, at: at));
      expect(l.missingIn(SubsCheckCat.noReply).map((m) => m.sub.username), ['on.dead']);
      expect(l.missingIn(SubsCheckCat.offline).map((m) => m.sub.username), ['off.dead', 'off.none']);
      // عبر الـVPN: الميّت غير المتّصل «غير متّصل» لا «لا يستجيب»
      final v = SubscribersCheck.vpn(subs, limits,
          reading: (s) => s.username == 'off.none' ? null : const VpnSubReading(src: 'dead'),
          readAt: (_) => at,
          running: false);
      expect(v.missingIn(SubsCheckCat.noReply).map((m) => (m.sub.username, m.why)), [('on.dead', SubsMissWhy.dead)]);
      expect(v.count(SubsCheckCat.offline), 2);
      // «كل الشركات»
      final m = SubscribersCheck.mixed(subs, limits,
          peek: (_) => null, reading: (s) => const VpnSubReading(src: 'dead'), readAt: (_) => at, vpnWaits: (_) => false);
      expect(m.missingIn(SubsCheckCat.noReply).single.sub.username, 'on.dead');
      expect(m.count(SubsCheckCat.offline), 2);
      for (final r in [l, v, m]) {
        expect(r.count(SubsCheckCat.problems) + r.count(SubsCheckCat.healthy), r.read);
        expect(SubsCheckCat.values.fold<int>(0, (n, c) => n + r.count(c)), r.total, reason: 'كلّ مشتركٍ بقسمٍ واحد');
      }
    });

    test('«جهازه ما ردّ» يجمع ما ردّ من شبكتك والميّت ومن يردّ بلا مقاييس عبر الـVPN — وكلٌّ بسببه؛ ومن لم يُسأل «لم يُفحص»', () {
      final subs = [_sub('dead'), _sub('ping'), _sub('auth'), _sub('none'), _sub('cpe0')];
      final reads = <String, VpnSubReading>{
        'dead': const VpnSubReading(src: 'dead'),
        'ping': const VpnSubReading(src: 'ping', ms: 7),
        'auth': const VpnSubReading(src: 'ping', ms: 9, err: 'login_failed'),
        'cpe0': const VpnSubReading(src: 'cpe'),
      };
      final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username], readAt: (_) => at, running: false);
      final noReply = {for (final m in r.missingIn(SubsCheckCat.noReply)) m.sub.username: SubscribersCheck.missText(m)};
      expect(noReply, {
        'dead': 'لا يستجيب',
        'ping': 'يردّ، ما انقرت مقاييسه',
        'auth': 'يردّ، ما انفتح برمزه المحفوظ',
      });
      // ١٠ نوفمبر: فحصٌ مكتمل بلا قراءةٍ له = الخادم لم يسأل جهازه (يوبيكويتي وحدها والمؤجَّل) ⇒ «لم يُفحص» بسببه
      final unchecked = r.missingIn(SubsCheckCat.unchecked).single;
      expect([unchecked.sub.username, SubscribersCheck.missText(unchecked)], ['none', 'لم يُقرأ عبر VPN']);
      expect(r.missingIn(SubsCheckCat.noMetrics).single.sub.username, 'cpe0', reason: 'ردّ بلا أرقام — ليس «ما ردّ»');
      expect(SubscribersCheck.missText(r.missingIn(SubsCheckCat.noMetrics).single), 'جهازه بلا مقاييس');
    });

    test('موجةٌ جارية: من لم يبلغه دوره «لم يُفحص بعد» لا «ما ردّ» — والقراءة القديمة تبقى، ومن خارج الموجة بنتيجته', () {
      final started = DateTime(2026, 11, 10, 9, 30);
      final old = started.subtract(const Duration(minutes: 9));
      final after = started.add(const Duration(seconds: 4));
      final subs = [
        _sub('t.wait', ip: '1'), // هدف ولم يبلغه دوره (فشلٌ قديم)
        _sub('t.new', ip: '2'), // هدف لا نتيجة له أصلاً
        _sub('t.dead', ip: '3'), // هدف فُحص في هذه الموجة وما ردّ
        _sub('t.old', ip: '4'), // هدف بقراءةٍ قديمة بمقاييس — تبقى (لا تقافز في «سليم»)
        _sub('x.dead', ip: '5'), // خارج الموجة (طازج) وما ردّ قبل دقيقتين
        _sub('t.off', online: false, ip: '6'), // هدفٌ غير متّصل
      ];
      final peeks = <String, ({DeviceHealthSnapshot? snap, bool stale, DateTime at})>{
        't.wait': (snap: null, stale: true, at: old),
        't.dead': (snap: null, stale: false, at: after),
        't.old': (snap: ok('4'), stale: true, at: old),
        'x.dead': (snap: null, stale: false, at: started.subtract(const Duration(minutes: 2))),
      };
      final wave = SubsWave.idle
          .start([for (final u in ['t.wait', 't.new', 't.dead', 't.old', 't.off']) SubsWave.keyOf(null, u)], started)
          .progress(1, 5);
      final r = SubscribersCheck.local(subs, limits, peek: (s) => peeks[s.username], wave: wave);
      final why = {for (final m in r.missing) m.sub.username: m.why};
      expect(why['t.wait'], SubsMissWhy.unchecked);
      expect(why['t.new'], SubsMissWhy.unchecked);
      expect(why['t.dead'], SubsMissWhy.noReply);
      expect(why['x.dead'], SubsMissWhy.noReply);
      expect(why['t.off'], SubsMissWhy.offline);
      expect(r.healthy.single.sub.username, 't.old');
      expect(SubscribersCheck.missText(r.missing.firstWhere((m) => m.sub.username == 't.wait'), running: true),
          'بانتظار الفحص');
      expect(SubsCheckCat.unchecked.labelFor(running: true), 'لم يُفحص بعد');
      // انتهت الموجة: لا «لم يُفحص بعد» — من لم يُسأل جهازه أصلاً «لم يصله الفحص»
      final done = SubscribersCheck.local(subs, limits, peek: (s) => peeks[s.username], wave: wave.finish(after));
      final why2 = {for (final m in done.missing) m.sub.username: m.why};
      expect(why2['t.wait'], SubsMissWhy.noReply, reason: 'نتيجته (فشلٌ) هي ما يُعرف');
      expect(why2['t.new'], SubsMissWhy.unchecked);
      expect(SubscribersCheck.missText(done.missing.firstWhere((m) => m.sub.username == 't.new')), 'لم يصله الفحص');
      expect(SubsCheckCat.unchecked.labelFor(), 'لم يُفحص');
    });

    test('عبر الـVPN: الجاري ⇒ «لم يُفحص بعد»، ولا فحص مكتمل ⇒ «لم يُفحص»، وفحصٌ مكتمل بلا قراءةٍ له ⇒ «لم يُفحص» بسببه', () {
      final subs = [_sub('a'), _sub('b')];
      VpnSubReading? read(Subscriber s) => s.username == 'a' ? const VpnSubReading(src: 'dead') : null;
      final running = SubscribersCheck.vpn(subs, limits, reading: read, readAt: (_) => at, running: true);
      expect([for (final m in running.missing) m.why], [SubsMissWhy.dead, SubsMissWhy.unchecked],
          reason: 'نتيجة الفحص السابق تبقى؛ من لا نتيجة له لم يبلغه الفحص');
      final never = SubscribersCheck.vpn(subs, limits, reading: (_) => null, readAt: (_) => null, running: false);
      expect(never.count(SubsCheckCat.noReply), 0, reason: 'لا فحص ⇒ لا «ما ردّ» كاذبة');
      expect(never.missing.first.note, 'لم يُفحص عبر VPN بعد');
      final done = SubscribersCheck.vpn(subs, limits, reading: read, readAt: (_) => at, running: false);
      expect([for (final m in done.missingIn(SubsCheckCat.noReply)) m.why], [SubsMissWhy.dead],
          reason: 'من سأله الخادم وما ردّ تأتي قراءته dead');
      expect([for (final m in done.missingIn(SubsCheckCat.unchecked)) (m.sub.username, m.note)], [('b', 'لم يُقرأ عبر VPN')],
          reason: 'لا قراءة بعد فحصٍ مكتمل = لم يُسأل جهازه');
    });

    test('١٠ نوفمبر · «كل الشركات» خارج الشبكة أو بـ«وضع VPN»: فشل فحص الهاتف ليس «ما ردّ من شبكتك»', () {
      final subs = [_sub('l.fail', company: 'kL', ip: '10.0.0.5'), _sub('l.ok', company: 'kL', ip: '10.0.0.6')];
      final peeks = <String, ({DeviceHealthSnapshot? snap, bool stale, DateTime at})>{
        'l.fail': (snap: null, stale: false, at: at),
        'l.ok': (snap: ok('6'), stale: false, at: at),
      };
      SubsCheckReport run({required bool onNet, DateTime? checked}) => SubscribersCheck.mixed(subs, limits,
          peek: (s) => peeks[s.username], reading: (_) => null, readAt: (_) => checked, localFailsFor: (_) => onNet);
      final on = run(onNet: true);
      expect(on.missingIn(SubsCheckCat.noReply).single.sub.username, 'l.fail', reason: 'على الشبكة: سُئل جهازه وما ردّ');
      expect(SubscribersCheck.missText(on.missingIn(SubsCheckCat.noReply).single), 'ما ردّ من شبكتك');
      final off = run(onNet: false);
      expect(off.count(SubsCheckCat.noReply), 0, reason: 'خارجها لا يصل الهاتف شيئاً');
      expect(off.missingIn(SubsCheckCat.unchecked).single.sub.username, 'l.fail');
      final offChecked = run(onNet: false, checked: at);
      expect(SubscribersCheck.missText(offChecked.missingIn(SubsCheckCat.unchecked).single), 'لم يُقرأ عبر VPN',
          reason: 'شركته فُحصت عبر الـVPN ولم يُسأل جهازه');
      // على شبكة المفتوحة: مشترك شركةٍ أخرى طريقها VPN شركتها — فشل الهاتف معه ليس شهادةً على جهازه
      final other = SubscribersCheck.mixed([_sub('v.fail', company: 'kV', ip: '10.9.0.5'), ...subs], limits,
          peek: (s) => s.username == 'v.fail' ? (snap: null, stale: false, at: at) : peeks[s.username],
          reading: (_) => null,
          readAt: (_) => at,
          localFailsFor: (c) => c == 'kL');
      expect(other.missingIn(SubsCheckCat.noReply).map((m) => m.sub.username), ['l.fail']);
      expect([for (final m in other.missingIn(SubsCheckCat.unchecked)) (m.sub.username, m.note)],
          [('v.fail', 'لم يُقرأ عبر VPN')]);
      for (final r in [on, off, offChecked, other]) {
        expect(r.healthy.single.sub.username, 'l.ok', reason: 'القراءة الناجحة قراءةٌ من أيّ مكان');
        expect(SubsCheckCat.values.fold<int>(0, (n, c) => n + r.count(c)), r.total, reason: 'كلّ مشتركٍ بقسمٍ واحد');
      }
    });

    test('«كل الشركات»: شركةٌ يفحصها الخادم الآن أو بعدها بالدور ⇒ «لم يُفحص بعد»؛ بلا طريق ⇒ «لم يُفحص» بسببها', () {
      final subs = [_sub('e.q', company: 'kE'), _sub('x.q', company: 'kX'), _sub('d.q', company: 'kD'), _sub('s.w', company: 'kS', ip: '9')];
      final started = DateTime(2026, 11, 10, 10);
      final wave = SubsWave.idle.start([SubsWave.keyOf('kS', 's.w')], started);
      final r = SubscribersCheck.mixed(subs, limits,
          peek: (_) => null,
          reading: (_) => null,
          readAt: (c) => c == 'kD' ? at : null,
          companyNote: (c) => c == 'kX' ? '«ثالثة» تحتاج VPN' : null,
          wave: wave,
          vpnWaits: (c) => c == 'kE');
      final miss = {for (final m in r.missing) m.sub.username: (m.why, m.note)};
      expect(miss['e.q'], (SubsMissWhy.unchecked, null), reason: 'شركته بالدور');
      expect(miss['s.w'], (SubsMissWhy.unchecked, null), reason: 'الموجة لم تبلغه');
      expect(miss['x.q'], (SubsMissWhy.company, '«ثالثة» تحتاج VPN'));
      expect(miss['d.q'], (SubsMissWhy.unchecked, 'لم يُقرأ عبر VPN'), reason: 'فُحصت شركته ولم يُسأل جهازه');
      expect(r.count(SubsCheckCat.unchecked), 4);
      expect(r.count(SubsCheckCat.noReply), 0);
      expect(SubscribersCheck.missText(r.missing.firstWhere((m) => m.sub.username == 'x.q')), 'شركته تحتاج VPN');
    });

    test('داخل السبب الواحد بترتيب القائمة (sort غير مستقرّ كان يقافز الصفوف)', () {
      final subs = [for (var i = 0; i < 80; i++) _sub('u${i.toString().padLeft(2, '0')}', online: i.isOdd)];
      final r = SubscribersCheck.local(subs, limits, peek: (_) => (snap: null, stale: false, at: at));
      expect(r.missingIn(SubsCheckCat.offline).map((m) => m.sub.username).toList(),
          [for (var i = 0; i < 80; i += 2) 'u${i.toString().padLeft(2, '0')}']);
      expect(r.missingIn(SubsCheckCat.noReply).map((m) => m.sub.username).toList(),
          [for (var i = 1; i < 80; i += 2) 'u${i.toString().padLeft(2, '0')}']);
    });
  });

  group('١٠ نوفمبر — الشريط يعدّ الفحص لا المقروء', () {
    final at = DateTime(2026, 11, 10, 9, 41);
    final started = DateTime(2026, 11, 10, 9, 40);

    test('من الهاتف: جارٍ «يفحص… 12 من 30» بتقدّم الموجة، وانتهى «انتهى الفحص — 113 مشترك» ممتلئاً بوقته', () {
      final w = SubsWave.idle.start(const ['|a'], started);
      final p0 = SubscribersCheck.progress(subs: 113, wave: w, at: at);
      expect([p0.state, p0.text, p0.value], [SubsRunState.running, 'يفحص…', null], reason: 'قبل أوّل نتيجة: بلا عدد');
      final p = SubscribersCheck.progress(subs: 113, wave: w.progress(12, 30), at: at);
      expect([p.state, p.text, p.value], [SubsRunState.running, 'يفحص… 12 من 30', 0.4]);
      final end = w.progress(30, 30).finish(at);
      final f = SubscribersCheck.progress(subs: 113, wave: end, at: end.endedAt);
      expect([f.state, f.text, f.value, f.at], [SubsRunState.finished, 'انتهى الفحص — 113 مشترك', 1.0, at]);
      // صورة المالك: ٥٨ مقروءاً من ١١٣ والموجة انتهت ⇒ لا «51%» عالقة
      expect(f.value, 1.0);
      expect(SubscribersCheck.progress(subs: 113, wave: SubsWave.idle).state, SubsRunState.idle);
      expect(SubscribersCheck.progress(subs: 113, wave: SubsWave.idle).text, 'لم يُفحص بعد');
    });

    test('عبر الـVPN: «يفحص… 120 من 310»، ومراحل الخادم بكلماتها، ثمّ «انتهى الفحص» أو سبب التعذّر', () {
      SubsVpnRun run({bool busy = true, bool failed = false, String? line, int done = 0, int total = 0, double? value}) =>
          (busy: busy, failed: failed, line: line, done: done, total: total, value: value);
      final p = SubscribersCheck.progress(subs: 310, vpn: run(line: 'يفحص مشتركينك… 120 من 310', done: 120, total: 310));
      expect([p.state, p.text], [SubsRunState.running, 'يفحص… 120 من 310']);
      expect(p.value, closeTo(120 / 310, 1e-9));
      final s = SubscribersCheck.progress(subs: 310, vpn: run(line: 'يقرأ السكترات…'));
      expect([s.state, s.text, s.value], [SubsRunState.running, 'يقرأ السكترات…', null]);
      final f = SubscribersCheck.progress(subs: 310, vpn: run(busy: false), at: at);
      expect([f.state, f.text, f.value], [SubsRunState.finished, 'انتهى الفحص — 310 مشترك', 1.0]);
      final x = SubscribersCheck.progress(subs: 310, vpn: run(busy: false, failed: true, line: 'الـVPN ما اتّصل الآن — حاول بعد قليل'), at: at);
      expect([x.state, x.text, x.value], [SubsRunState.failed, 'الـVPN ما اتّصل الآن — حاول بعد قليل', null]);
      expect(SubscribersCheck.progress(subs: 310, vpn: run(busy: false)).state, SubsRunState.idle, reason: 'لم يُفحص قطّ');
    });

    test('«كل الشركات»: موجة شبكتك ثمّ الخادم باسم الشركة، وانتهى حين ينتهي الاثنان — وتعذّر VPN شركةٍ لا يُبطل الباقي', () {
      final w = SubsWave.idle.start(const ['k|a'], started).progress(3, 9);
      SubsVpnRun run({bool busy = true, bool failed = false, int done = 0, int total = 0}) =>
          (busy: busy, failed: failed, line: null, done: done, total: total, value: null);
      final a = SubscribersCheck.progress(subs: 149, wave: w, vpn: run(done: 9, total: 22), merged: true, vpnCompany: 'ايرث لنك');
      expect(a.text, 'يفحص من شبكتك… 3 من 9');
      final b = SubscribersCheck.progress(
          subs: 149, wave: w.finish(at), vpn: run(done: 9, total: 22), merged: true, vpnCompany: 'ايرث لنك', at: at);
      expect([b.state, b.text], [SubsRunState.running, 'يفحص… 9 من 22 · «ايرث لنك» عبر VPN']);
      final c = SubscribersCheck.progress(subs: 149, wave: w.finish(at), vpn: run(), merged: true, vpnCompany: 'ايرث لنك', at: at);
      expect([c.text, c.value], ['يفحص «ايرث لنك» عبر VPN…', null]);
      final d = SubscribersCheck.progress(subs: 149, wave: w.finish(at), vpn: run(busy: false), merged: true, at: at);
      expect([d.state, d.text, d.value], [SubsRunState.finished, 'انتهى الفحص — 149 مشترك', 1.0]);
      final e = SubscribersCheck.progress(subs: 149, wave: w.finish(at), vpn: run(busy: false, failed: true), merged: true, at: at);
      expect(e.state, SubsRunState.finished, reason: 'شبكتك فُحصت؛ الشركة التي تعذّرت تُسمّى ببطاقة الشركات');
    });

    test('SubsWave: البدء يحفظ آخر انتهاء، والتقدّم يعدّ، والقطع بلا أهداف ينهي الجارية', () {
      final w = const SubsWave(endedAt: null).start(['|a', 'k|b'], started);
      expect([w.running, w.done, w.total, w.startedAt], [true, 0, 0, started]);
      expect(w.covers(_sub('A')), isTrue, reason: 'اليوزر بلا حساسيّة حروف');
      expect(w.covers(_sub('b', company: 'k')), isTrue);
      expect(w.covers(_sub('b')), isFalse, reason: 'شركته جزءٌ من مفتاحه');
      final p = w.progress(1, 2);
      expect([p.running, p.done, p.total, p.keys.length], [true, 1, 2, 2]);
      final f = p.finish(at);
      expect([f.running, f.endedAt, f.keys.isEmpty], [false, at, true]);
      expect(f.start(['|c'], at).endedAt, at, reason: 'موجةٌ جديدة: «انتهى» السابق محفوظ حتى تنتهي');
      expect(p.settle(at).running, isFalse);
      expect(f.settle(DateTime(2030)).endedAt, at, reason: 'لا جارية ⇒ كما هي');
    });

    test('VpnNowJob.waits: الحاليّة وما بعدها بالدور — لا ما فُحص قبلها في الفحص نفسه', () {
      final j = VpnNowJob(VpnNowKind.subscribers)
        ..phase = VpnBarPhase.running
        ..queue = ['k1', 'k2', 'k3']
        ..current = 'k2';
      expect([j.waits('k1'), j.waits('k2'), j.waits('k3'), j.waits('k9')], [false, true, true, false]);
      j.current = null;
      expect(j.waits('k1'), isTrue, reason: 'قبل أوّل شركة: الكلّ بالدور');
      j.phase = VpnBarPhase.done;
      expect(j.waits('k3'), isFalse);
    });
  });

  group('١٠ نوفمبر — التقرير المنسوخ بالأقسام نفسها', () {
    test('سطر الفحص والأعداد بأسمائها، ثمّ من بمشكلة ومن ما ردّ ومن لم يُفحص بأسبابهم — والسليم وغير المتّصل عدداً', () {
      final at = DateTime.now().subtract(const Duration(minutes: 3));
      final subs = [
        _sub('weak'), _sub('fine'), _sub('dead'), _sub('auth'), _sub('off', online: false), _sub('new', ip: '7'),
      ];
      final reads = <String, VpnSubReading>{
        'weak': const VpnSubReading(src: 'cpe', sig: -80, ccq: 90, lan: '100'),
        'fine': const VpnSubReading(src: 'cpe', sig: -50, ccq: 95, lan: '100'),
        'dead': const VpnSubReading(src: 'dead'),
        'auth': const VpnSubReading(src: 'ping', ms: 9, err: 'login_failed'),
      };
      final r = SubscribersCheck.vpn(subs, limits, reading: (s) => reads[s.username], readAt: (_) => null, running: false);
      final p = SubscribersCheck.progress(subs: r.total, vpn: (busy: false, failed: false, line: null, done: 0, total: 0, value: null), at: at);
      final text = SubscribersCheck.reportText(r, progress: p, source: 'عبر VPN');
      final lines = text.split('\n');
      expect(lines[0], 'الفحص العامّ للمشتركين — عبر VPN');
      expect(lines[1], 'انتهى الفحص — 6 مشترك · منذ 3 دقائق');
      expect(lines[2], 'بمشكلة 1 · سليم 1 · جهازه ما ردّ 2 · غير متّصل الآن 1 · لم يُفحص 1');
      expect(text, contains('بمشكلة (1):\n• weak (weak) — '));
      expect(text, contains('جهازه ما ردّ (2):\n• dead (dead) — لا يستجيب\n• auth (auth) — يردّ، ما انفتح برمزه المحفوظ'));
      expect(text, contains('لم يُفحص (1):\n• new (new) — لم يُفحص عبر VPN بعد'));
      expect(text, isNot(contains('• off')), reason: 'غير المتّصل عددٌ وحده — ليس عطلاً يُتابَع');
      expect(text, isNot(contains('• fine')));
      expect(text, isNot(contains('لم يُقرأ 5')), reason: 'لا «لم يُقرأ» تخلط الأقسام');
    });

    test('أثناء الفحص: «لم يكتمل» و«لم يُفحص بعد»، وشركة كلّ مشترك في «كل الشركات»', () {
      final started = DateTime.now();
      final subs = [_sub('w', company: 'kS', ip: '1')];
      final wave = SubsWave.idle.start([SubsWave.keyOf('kS', 'w')], started).progress(4, 10);
      final r = SubscribersCheck.local(subs, limits, peek: (_) => null, wave: wave);
      final text = SubscribersCheck.reportText(r,
          progress: SubscribersCheck.progress(subs: 1, wave: wave), companyOf: (s) => s.companyKey == 'kS' ? 'سوبرنت' : null);
      expect(text.split('\n')[1], 'يفحص… 4 من 10 — لم يكتمل');
      expect(text, contains('لم يُفحص بعد (1):\n• w (w · سوبرنت) — بانتظار الفحص'));
    });
  });
}
