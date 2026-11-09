import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/vpn_now_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/services/connection_alerts.dart';
import 'package:rad_mysvcs/services/subscribers_check.dart';
import 'package:rad_mysvcs/services/voice/voice_check.dart';

/// المراجعة ١٠ نوفمبر (إصدار 180) — «الفحص العامّ»: غير المتّصل الآن بقراءةٍ من قبل انقطاعه. ذاكرة الفحص تحفظ آخر
/// قراءةٍ مهما قدُمت، ومن انقطع (كهرباء) يفقد عنوان جلسته فلا تعيدها الموجة: كان يُعدّ «بمشكلة»/«سليم» بقراءة الصباح
/// والفحص مساءً، و«غير متّصل الآن» أقلّ من الحقيقة، والتقرير المنسوخ يلصق «• فلان — الكيبل 10 ميكا» بلا عمر.
/// القاعدة: قراءة غير المتّصل تُعدّ إن كانت من هذا الفحص — طازجةً أو من الموجة الجارية/الأخيرة — فالمطفأ يُفحص عمداً
/// (جهاز وصوله قد يكون حيّاً)؛ وإلّا فهو «غير متّصل الآن». المتّصل كما كان، وقراءة الـVPN بحدّها (٣٠ د).
Subscriber _sub(String u, {bool online = true, String? company, String? ip}) => Subscriber.fromJson({
      'username': u,
      'firstname': u,
      'lastname': '',
      'online_status': online ? 1 : 0,
      'remaining_days': 20,
      if (ip != null) 'ip': ip,
    }).withCompany(company);

DeviceHealthSnapshot _nano({String speed = '100Mbps-Full'}) => DeviceHealthSnapshot(
    kind: DeviceKind.ubiquiti,
    ip: '10.0.0.9',
    ubnt: UbiquitiStatus(
        hostname: 'Nano', firmware: 'XC.v8', uptimeSeconds: 1, ssid: 's', mode: 'sta', signalDbm: -55,
        noiseFloorDbm: -95, ccqPercent: 95, distanceMeters: 1, txRateKbps: 1, rxRateKbps: 1,
        lanPorts: [LanPort(name: 'eth0', speed: speed, plugged: true)], peerMac: null, peerCount: 1,
        baseUrl: 'http://x'));

typedef _Peek = ({DeviceHealthSnapshot? snap, bool stale, DateTime at});

void main() {
  const t = ConnectionAlertThresholds(signalDbm: -70, ccqPct: 70, fiberRxDbm: -25, fiberTempC: 70);
  ConnectionAlertThresholds limits(String? _) => t;
  final now = DateTime.now();
  final morning = now.subtract(const Duration(hours: 8)); // قبل انقطاعه
  // الموجة الأخيرة طويلة (حسابٌ كبير): ما قرأته قبل ٨ دقائق أقدم من مهلة الذاكرة لكنّه من هذا الفحص
  final started = now.subtract(const Duration(minutes: 9));
  final inWave = started.add(const Duration(minutes: 1));
  final wave = SubsWave.idle.start(const ['|off.wave'], started).finish(now.subtract(const Duration(minutes: 1)));

  final subs = [
    _sub('off.old', online: false), // كيبله 10 صباحاً ثمّ انقطع وفقد عنوانه
    _sub('off.fresh', online: false, ip: '10.0.0.8'), // مطفأ وجهاز وصوله حيّ — قُرئ للتوّ
    _sub('off.wave', online: false, ip: '10.0.0.9'), // مطفأ وقرأته الموجة الأخيرة (كيبله 10)
    _sub('on.old'), // متّصل بقراءةٍ قديمة — كما كان
  ];
  final peeks = <String, _Peek>{
    'off.old': (snap: _nano(speed: '10Mbps-Full'), stale: true, at: morning),
    'off.fresh': (snap: _nano(), stale: false, at: now.subtract(const Duration(minutes: 1))),
    'off.wave': (snap: _nano(speed: '10Mbps-Full'), stale: true, at: inWave),
    'on.old': (snap: _nano(), stale: true, at: morning),
  };

  Map<String, SubsCheckCat> cats(SubsCheckReport r) => {
        for (final x in r.rows) x.sub.username: SubsCheckCat.problems,
        for (final x in r.healthy) x.sub.username: SubsCheckCat.healthy,
        for (final m in r.missing) m.sub.username: SubscribersCheck.catOf(m.why),
      };

  test('من الهاتف: غير المتّصل بقراءة الصباح ⇒ «غير متّصل الآن» لا «بمشكلة»، والتقرير المنسوخ لا يلصقها', () {
    final r = SubscribersCheck.local(subs, limits, peek: (s) => peeks[s.username], wave: wave);
    expect(cats(r), {
      'off.old': SubsCheckCat.offline,
      'off.fresh': SubsCheckCat.healthy,
      'off.wave': SubsCheckCat.problems,
      'on.old': SubsCheckCat.healthy,
    });
    expect([r.read, r.count(SubsCheckCat.offline)], [3, 1]);
    final text = SubscribersCheck.reportText(r,
        progress: SubscribersCheck.progress(subs: r.total, wave: wave, at: wave.endedAt));
    expect(text, isNot(contains('off.old')),
        reason: 'غير المتّصل عددٌ وحده — لا «• off.old — الكيبل 10» بقراءة الصباح');
    expect(text, contains('• off.wave (off.wave) — '), reason: 'قراءة هذا الفحص تُعدّ ولو كان مطفأً');
    // الأمر الصوتيّ للمشترك نفسه بكلمة قسمه
    expect(SubscriberVoiceCheck(subs.first).headline, 'فعّال و${SubsCheckCat.offline.label}');
  });

  test('بلا موجةٍ معروفة: الطازجة وحدها تُعدّ لغير المتّصل', () {
    final r = SubscribersCheck.local(subs, limits, peek: (s) => peeks[s.username]);
    expect(cats(r), {
      'off.old': SubsCheckCat.offline,
      'off.fresh': SubsCheckCat.healthy,
      'off.wave': SubsCheckCat.offline,
      'on.old': SubsCheckCat.healthy,
    });
    expect(SubscribersCheck.currentFor(subs[1], peeks['off.fresh']!, null), isTrue);
    expect(SubscribersCheck.currentFor(subs[3], peeks['on.old']!, null), isTrue, reason: 'المتّصل كما كان');
  });

  test('«كل الشركات»: القاعدة نفسها لقراءة الهاتف — وقراءة VPN شركته (حتى ٣٠ د) تُعدّ بعمرها', () {
    final vpnAt = now.subtract(const Duration(minutes: 6));
    final all = [
      ...[for (final s in subs) s.withCompany('kS')],
      _sub('off.vpn', online: false, company: 'kE'), // قراءة هاتفٍ قديمة وقراءة VPN حديثة لشركته
      _sub('off.dead', online: false, company: 'kE'), // قراءة هاتفٍ قديمة والـVPN «لا يستجيب»
    ];
    final r = SubscribersCheck.mixed(all, limits,
        peek: (s) => peeks[s.username] ?? (snap: _nano(), stale: true, at: morning),
        reading: (s) => switch (s.username) {
              'off.vpn' => const VpnSubReading(src: 'cpe', sig: -58, ccq: 93, lan: '10'),
              'off.dead' => const VpnSubReading(src: 'dead'),
              _ => null,
            },
        readAt: (c) => c == 'kE' ? vpnAt : null,
        wave: wave,
        vpnWaits: (_) => false,
        localFailsFor: (c) => c == 'kS');
    expect(cats(r), {
      'off.old': SubsCheckCat.offline,
      'off.fresh': SubsCheckCat.healthy,
      'off.wave': SubsCheckCat.problems,
      'on.old': SubsCheckCat.healthy,
      'off.vpn': SubsCheckCat.problems,
      'off.dead': SubsCheckCat.offline,
    });
    final viaVpn = r.rows.firstWhere((x) => x.sub.username == 'off.vpn').reading!;
    expect([viaVpn.vpn, viaVpn.at], [true, vpnAt], reason: 'قراءة الـVPN بوقتها لا بقراءة الهاتف القديمة');
    expect(SubsCheckCat.values.fold<int>(0, (n, c) => n + r.count(c)), r.total, reason: 'كلّ مشتركٍ بقسمٍ واحد');
  });
}
