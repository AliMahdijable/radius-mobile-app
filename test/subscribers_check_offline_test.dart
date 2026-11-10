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

  // المراجعة الثانية: موجة القائمة قرأت كيبله 10 قبل ٦ دقائق، ثمّ بدأت موجة «الفحص العامّ» قبل ٤ دقائق وتركته (طازجٌ
  // حينها) — كان يسقط بعد ٥ دقائق إلى «غير متّصل الآن» بلا فحصٍ جديد، و«بمشكلة» تنقص والتقرير ينساه. ومن كانت قراءته
  // قديمةً حين بدأت (أعادته الموجة ولا عنوان لها) يبقى «غير متّصل الآن».
  test('المراجعة الثانية: قراءةٌ تركتها الموجة طازجةً تُعدّ بعد ٥ دقائق — والقديمة حين بدأت لا', () {
    final kept = (snap: _nano(speed: '10Mbps-Full'), stale: true, at: now.subtract(const Duration(minutes: 6)));
    final before = (snap: _nano(), stale: true, at: now.subtract(const Duration(minutes: 10)));
    final waveStart = now.subtract(const Duration(minutes: 4));
    final waves = {
      'جارية': SubsWave.idle.start(const ['|other'], waveStart),
      'انتهت': SubsWave.idle.start(const ['|other'], waveStart).finish(now.subtract(const Duration(minutes: 3))),
    };
    final x = _sub('off.kept', online: false, ip: '10.0.0.9'); // جهاز وصوله حيّ وخطّه مقطوع
    final y = _sub('off.before', online: false);
    _Peek? peek(Subscriber s) => s.username == 'off.kept' ? kept : before;
    for (final w in waves.entries) {
      final l = SubscribersCheck.local([x, y], limits, peek: peek, wave: w.value);
      expect(cats(l), {'off.kept': SubsCheckCat.problems, 'off.before': SubsCheckCat.offline}, reason: w.key);
      expect(SubscribersCheck.reportText(l, progress: SubscribersCheck.progress(subs: 2, wave: w.value, at: now)),
          contains('• off.kept (off.kept) — '),
          reason: 'التقرير المنسوخ يذكره');
      final m = SubscribersCheck.mixed([x.withCompany('kS'), y.withCompany('kS')], limits,
          peek: peek,
          reading: (_) => null,
          readAt: (_) => null,
          wave: w.value,
          vpnWaits: (_) => false,
          localFailsFor: (c) => c == 'kS');
      expect(cats(m), {'off.kept': SubsCheckCat.problems, 'off.before': SubsCheckCat.offline}, reason: w.key);
    }
    expect(SubscribersCheck.currentFor(x, kept, null), isFalse, reason: 'بلا موجةٍ معروفة: الطازجة وحدها');
  });

  // المراجعة الثالثة: آخر اتّصاله من المزوّد (last_online بتوقيت بغداد) — قراءةٌ أقدم منه من قبل انقطاعه يقيناً ⇒
  // «غير متّصل الآن» ولو طازجة أو تركتها الموجة (انقطعت الكهرباء بعد قراءته بدقائق: كان «سليم» حتى «تحديث»). وبعده
  // تبقى قاعدة الموجة: ايرث لنك تعطي آخر «دخول» (بدء جلسته) حين لا تحضر جلساتها المنتهية.
  test('المراجعة الثالثة: قراءةٌ من قبل آخر اتّصاله ⇒ «غير متّصل الآن» ولو طازجة؛ وبعده كما كانت', () {
    DateTime ago(int m) => now.subtract(Duration(minutes: m));
    String sas(DateTime t) => t.toIso8601String().substring(0, 19).replaceFirst('T', ' ');
    Subscriber off(String u, String? last, {String? ip}) => Subscriber.fromJson({
          'username': u,
          'firstname': u,
          'lastname': '',
          'online_status': 0,
          'remaining_days': 20,
          if (ip != null) 'ip': ip,
          if (last != null) 'last_online': last,
        });
    // موجةٌ بدأت قبل ٢١ دقيقة وانتهت قبل ٢٠
    final w = SubsWave.idle.start(const ['|other'], ago(21)).finish(ago(20));
    final subs = [
      off('cut.wave', sas(ago(22))), // قُرئ سليماً قبل ٢٥ د ثمّ انقطع قبل ٢٢ د — والموجة تركتها (عمرها ٤ د حين بدأت)
      off('cut.fresh', sas(ago(1))), // قُرئ قبل ٤ د ثمّ انقطع قبل دقيقة
      off('line.down', sas(ago(30)), ip: '10.0.0.9'), // انقطع قبل ٣٠ د وجهازه حيّ: قرأته الموجة بعدها
      off('el.login', sas(now.subtract(const Duration(hours: 9)))), // آخر «دخول» — قراءة الصباح من أثناء جلسته
      off('zero.last', '0000-00-00 00:00:00'), // صفر الساس غياب ⇒ قاعدة الموجة (طازجةٌ حين بدأت)
    ];
    final peeks = <String, _Peek>{
      'cut.wave': (snap: _nano(), stale: true, at: ago(25)),
      'cut.fresh': (snap: _nano(), stale: false, at: ago(4)),
      'line.down': (snap: _nano(speed: '10Mbps-Full'), stale: true, at: ago(21)),
      'el.login': (snap: _nano(), stale: true, at: morning),
      'zero.last': (snap: _nano(), stale: true, at: ago(24)),
    };
    const expected = {
      'cut.wave': SubsCheckCat.offline,
      'cut.fresh': SubsCheckCat.offline,
      'line.down': SubsCheckCat.problems,
      'el.login': SubsCheckCat.offline,
      'zero.last': SubsCheckCat.healthy,
    };
    final l = SubscribersCheck.local(subs, limits, peek: (s) => peeks[s.username], wave: w);
    expect(cats(l), expected);
    expect(SubscribersCheck.reportText(l, progress: SubscribersCheck.progress(subs: l.total, wave: w, at: w.endedAt)),
        contains('بمشكلة 1 · سليم 1 · غير متّصل الآن 3'));
    final m = SubscribersCheck.mixed([for (final s in subs) s.withCompany('kS')], limits,
        peek: (s) => peeks[s.username],
        reading: (_) => null,
        readAt: (_) => null,
        wave: w,
        vpnWaits: (_) => false,
        localFailsFor: (c) => c == 'kS');
    expect(cats(m), expected);
  });

  // المراجعة الثالثة: موجةٌ جديدة تعيد قراءة غير المتّصل (قدُمت عن ٥ د) — كان يسقط إلى «غير متّصل الآن» من بدئها حتى
  // تبلغه، و«بمشكلة» تنقص والنسخ ينساه، والمتّصل بالقراءة نفسها يبقى. تُقاس ببدء الموجة التي قبلها حتى تستبدلها.
  test('المراجعة الثالثة: موجةٌ تغطّيه ولم تبلغه ⇒ قراءته التي عُدّت قبلها تبقى «بمشكلة» حتى تستبدلها', () {
    final x = _sub('off.kept', online: false, ip: '10.0.0.9');
    final y = _sub('off.before', online: false, ip: '10.0.0.8');
    final z = _sub('on.kept', ip: '10.0.0.7'); // المتّصل بالقراءة نفسها
    final kept = (snap: _nano(speed: '10Mbps-Full'), stale: true, at: now.subtract(const Duration(minutes: 6)));
    final peeks = <String, _Peek>{
      'off.kept': kept,
      'on.kept': kept,
      'off.before': (snap: _nano(), stale: true, at: now.subtract(const Duration(minutes: 10))),
    };
    // الأخيرة بدأت قبل ٤ د بلاه (طازجٌ حينها) وانتهت، والجديدة بدأت الآن تغطّي الثلاثة
    final last = SubsWave.idle.start(const ['|other'], now.subtract(const Duration(minutes: 4))).finish(now);
    final next = last.start([for (final u in peeks.keys) SubsWave.keyOf(null, u)], now);
    for (final w in [last, next, next.progress(1, 3)]) {
      final r = SubscribersCheck.local([x, y, z], limits, peek: (s) => peeks[s.username], wave: w);
      expect(cats(r),
          {'off.kept': SubsCheckCat.problems, 'off.before': SubsCheckCat.offline, 'on.kept': SubsCheckCat.problems},
          reason: w.running ? 'الجديدة لم تبلغه' : 'قبلها');
      expect(SubscribersCheck.reportText(r, progress: SubscribersCheck.progress(subs: 3, wave: w, at: now)),
          contains('• off.kept (off.kept) — '));
      final m = SubscribersCheck.mixed([x, y, z], limits,
          peek: (s) => peeks[s.username],
          reading: (_) => null,
          readAt: (_) => null,
          wave: w,
          vpnWaits: (_) => false,
          localFailsFor: (_) => true);
      expect(cats(m)['off.kept'], SubsCheckCat.problems);
    }
  });
}
