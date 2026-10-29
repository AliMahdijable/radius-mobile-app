import 'package:flutter/foundation.dart';

import '../../../api/mikrotik_api.dart';
import '../../../api/mimosa_api.dart';
import '../../../api/ubnt_api.dart';
import '../../../api/vsol_olt_api.dart';
import '../device_vitals.dart';

/// قراءة جهازٍ كما يحتاجها البرج — من جلسة قسم الأجهزة نفسها ([DeviceVitals.fetch]، لا جلسةٌ ثانية).
///
/// كلّ حقلٍ لا يقرؤه الجهاز `null` يُعرض «—»، لا صفر: الصفر رقمٌ يكذب (قاعدة القسم).
@immutable
class TowerReading {
  const TowerReading({
    required this.at,
    this.wireless = false,
    this.mode,
    this.clients,
    this.quality,
    this.signal,
    this.downBps,
    this.upBps,
    this.frequency,
    this.channelWidth,
    this.noise,
    this.linkSpeed,
    this.uptime,
    this.temperature,
    this.cpu,
    this.peers = const [],
    this.portsUp,
    this.portsTotal,
    this.busiestPort,
    this.poeWatts,
    this.voltage,
    this.olt,
  });

  final DateTime at;

  /// للجهاز واجهةٌ لاسلكيّة شغّالة (سكتر/لنك/لوحة) — لا راوتر ولا سويج.
  final bool wireless;

  /// وضع الواجهة كما يكتبه الجهاز: `ap-bridge` · `station` · `bridge` (مايكروتك)، `ap` · `sta` (يوبنتي).
  final String? mode;

  /// المتّصلون عليه الآن (المشتركون للسكتر، والطرف الآخر للّنك).
  final int? clients;

  /// متوسّط CCQ للمتّصلين (أو CCQ الوصلة نفسها).
  final int? quality;

  /// متوسّط إشارة المتّصلين بالـdBm (أو إشارة الجهاز نفسه إن كان مستقبِلاً).
  final int? signal;

  /// التنزيل نحو المشتركين والرفع منهم (بت/ثانية) على الواجهة اللاسلكيّة، وإلّا أنشط منفذ.
  final int? downBps;
  final int? upBps;

  final int? frequency;
  final int? channelWidth;
  final int? noise;

  /// سرعة منفذ الشبكة السلكيّ («1Gbps» · «100Mbps»).
  final String? linkSpeed;
  final String? uptime;
  final int? temperature;
  final int? cpu;

  /// المتّصلون واحداً واحداً — منها «أضعف المشتركين».
  final List<PeerLink> peers;

  /// للسويج والراوتر (الكابينة) — المالك ٢٧ أكتوبر: «اجهزه السويجات ما يظهر بيها شي بعرض البرج».
  /// منافذ الشبكة السلكيّة الشغّالة من مجموعها، وأنشطها الآن، واستهلاك الـPoE والفولتيّة إن قرأها الطراز.
  final int? portsUp;
  final int? portsTotal;
  final PortTraffic? busiestPort;
  final double? poeWatts;
  final double? voltage;

  /// أولت — المالك ٢٩ أكتوبر: «الاولتي مجاي يجلب بيانات في وضع البرج». من لقطة البنية نفسها التي تملأ بطاقة الجدار
  /// ([VsolOltStats])؛ `null` لغير الأولت.
  final OltSummary? olt;

  /// نقطة وصول (تخدم مشتركين) لا مستقبِل.
  bool get isAccessPoint {
    final m = (mode ?? '').toLowerCase();
    if (m.isEmpty) return (clients ?? 0) >= 2;
    return m.startsWith('ap') || m == 'bridge' || m.contains('master');
  }

  /// مستقبِلٌ متّصل بنقطة وصولٍ واحدة (طرف لنك أو جهاز مشترك).
  bool get isStation {
    final m = (mode ?? '').toLowerCase();
    return m.startsWith('sta') || m.contains('station') || m.contains('slave');
  }

  static int? _avg(Iterable<int?> xs, {bool skipZero = true}) {
    var n = 0;
    var sum = 0;
    for (final x in xs) {
      if (x == null || (skipZero && x == 0)) continue;
      n++;
      sum += x;
    }
    return n == 0 ? null : (sum / n).round();
  }

  static bool _isWirelessPort(String name) {
    final n = name.toLowerCase();
    return n.startsWith('wlan') || n.startsWith('ath') || n.startsWith('wifi') || n.startsWith('wl');
  }

  static bool _isEtherPort(String name) {
    final n = name.toLowerCase();
    return n.startsWith('ether') || n.startsWith('eth') || n.startsWith('lan') || n.startsWith('sfp');
  }

  /// يبني القراءة من حصيلة جلسةٍ واحدة. [r.raw] يحدّد العلامة.
  static TowerReading fromProbe(ProbeResult r, {DateTime? at}) {
    final when = at ?? DateTime.now();
    final raw = r.raw;
    final peers = r.detail.peers;
    final ports = r.detail.ports;

    var wireless = false;
    String? mode;
    int? frequency;
    int? channelWidth;
    int? noise;
    int? temperature;
    int? cpu;
    int? ownSignal;
    int? ownQuality;
    String? linkSpeed;
    double? poeWatts;
    double? voltage;
    OltSummary? olt;

    if (raw is MikrotikStats) {
      final radios = raw.wirelessInterfaces.where((w) => !w.disabled).toList()
        ..sort((a, b) => (b.running ? 1 : 0) - (a.running ? 1 : 0));
      wireless = radios.isNotEmpty;
      if (wireless) {
        final w = radios.first;
        mode = w.mode.isEmpty ? null : w.mode;
        frequency = w.frequency > 0 ? w.frequency : null;
        channelWidth = w.channelWidth > 0 ? w.channelWidth : null;
      }
      temperature = raw.temperature;
      // SwOS عبر SNMP لا يحمل المعالج — لا «0٪».
      cpu = raw.cpuKnown ? raw.cpuLoad : null;
      poeWatts = raw.powerWatts;
      voltage = raw.voltage;
    } else if (raw is UbntStats) {
      final w = raw.wireless;
      wireless = w != null;
      if (w != null) {
        mode = w.mode.isEmpty ? null : w.mode;
        frequency = w.frequency > 0 ? w.frequency : null;
        channelWidth = w.chanbw > 0 ? w.chanbw : null;
        noise = w.hasNoise ? w.noise : null;
        ownSignal = w.signal == 0 ? null : w.signal;
        ownQuality = w.hasCcq ? w.ccq : null;
      }
      temperature = raw.host.temperature > 0 ? raw.host.temperature : null;
      cpu = raw.host.cpuload;
      linkSpeed = raw.lanSpeed;
    } else if (raw is MimosaStats) {
      wireless = true;
      mode = switch (raw.wirelessMode) { 1 => 'ap', 2 => 'sta', _ => null };
      channelWidth = raw.channelWidthMhz;
      temperature = raw.temperatureC?.round();
      ownSignal = raw.totalRxPowerDbm?.round();
    } else if (raw is VsolOltStats) {
      olt = OltSummary.of(raw);
      // BDCOM/HSGQ تقرأ المعالج وحرارة الصندوق؛ VSOL بلا مجسّ معالج في SNMP ⇒ «—» لا صفر.
      cpu = raw.chassis?.cpuPct;
      temperature = raw.chassis?.boxTempC;
    }

    // المنفذ اللاسلكيّ يحمل حِمل المشتركين؛ بلا واحدٍ (راوتر/سويج) نأخذ أنشط منفذ.
    PortTraffic? radioPort;
    PortTraffic? busiest;
    for (final p in ports) {
      if (!p.up) continue;
      if (radioPort == null && _isWirelessPort(p.name)) radioPort = p;
      final load = (p.rxBps ?? 0) + (p.txBps ?? 0);
      final best = busiest == null ? -1 : (busiest.rxBps ?? 0) + (busiest.txBps ?? 0);
      if (load > best) busiest = p;
    }
    if (linkSpeed == null) {
      for (final p in ports) {
        if (p.up && _isEtherPort(p.name) && (p.linkSpeed ?? '').isNotEmpty) {
          linkSpeed = p.linkSpeed;
          break;
        }
      }
    }

    int? down;
    int? up;
    final probeAp = wireless && peers.length >= 2;
    final station = (mode ?? '').toLowerCase().startsWith('sta') || (mode ?? '').toLowerCase().contains('station');
    if (radioPort != null) {
      final rx = radioPort.rxBps;
      final tx = radioPort.txBps;
      if (station) {
        // مستقبِل (sta): ينزّل ما يستقبله (rx) ويرفع ما يرسله (tx).
        down = rx;
        up = tx;
      } else if (probeAp) {
        // نقطة وصولٍ تخدم مشتركين (≥٢ أطراف): التنزيل = ما تُرسله إليهم (tx).
        down = tx;
        up = rx;
      } else {
        // لنك PtP (طرفٌ واحد): مود AirFiber «master/slave» لا يدلّ على الاتّجاه، فكان يُحسب
        // tx تنزيلاً فيُقلَب (الرفع يظهر مكان التنزيل). التنزيل = الاتّجاه الأكبر (الوارد للبرج غالباً).
        down = rx == null && tx == null ? null : ((rx ?? 0) >= (tx ?? 0) ? rx : tx);
        up = rx == null && tx == null ? null : ((rx ?? 0) >= (tx ?? 0) ? tx : rx);
      }
    } else if (busiest != null) {
      final rx = busiest.rxBps;
      final tx = busiest.txBps;
      down = rx == null && tx == null ? null : ((rx ?? 0) >= (tx ?? 0) ? rx : tx);
      up = rx == null && tx == null ? null : ((rx ?? 0) >= (tx ?? 0) ? tx : rx);
    }

    final wired = [for (final p in ports) if (_isEtherPort(p.name) || !_isWirelessPort(p.name)) p];
    final peerQuality = _avg(peers.map((p) => p.ccq));
    final peerSignal = _avg(peers.map((p) => p.signal));
    return TowerReading(
      at: when,
      wireless: wireless,
      mode: mode,
      clients: wireless ? peers.length : null,
      quality: peerQuality ?? ownQuality,
      signal: (station || !probeAp) ? (ownSignal ?? peerSignal) : (peerSignal ?? ownSignal),
      downBps: down,
      upBps: up,
      frequency: frequency,
      channelWidth: channelWidth,
      noise: noise,
      linkSpeed: linkSpeed,
      uptime: r.detail.uptime,
      temperature: temperature,
      cpu: cpu,
      peers: peers,
      portsUp: wired.isEmpty ? null : wired.where((p) => p.up).length,
      portsTotal: wired.isEmpty ? null : wired.length,
      busiestPort: busiest != null && busiest.total > 0 ? busiest : null,
      poeWatts: poeWatts,
      voltage: voltage,
      olt: olt,
    );
  }
}

/// خلاصة أولت للبرج: المشتركون (ONU) المتّصلون من مجموعهم، ومنافذ PON واحداً واحداً، ومنافذ الربط.
@immutable
class OltSummary {
  const OltSummary({
    required this.onusOnline,
    required this.onusTotal,
    required this.pons,
    required this.uplinksUp,
    required this.uplinksTotal,
    this.ramMb,
  });

  factory OltSummary.of(VsolOltStats s) => OltSummary(
        onusOnline: s.onusOnline,
        onusTotal: s.onusTotal,
        pons: [
          for (final p in s.ponPorts) (label: p.label, up: p.up, online: p.onuOnline, total: p.onuTotal),
        ],
        uplinksUp: s.uplinks.where((u) => u.up).length,
        uplinksTotal: s.uplinks.length,
        // الإجماليّ وحده (BDCOM) — لا نسبة استخدام.
        ramMb: s.chassis?.ramBytes == null ? null : (s.chassis!.ramBytes! / (1024 * 1024)).round(),
      );

  final int onusOnline;
  final int onusTotal;
  final List<({String label, bool up, int online, int total})> pons;
  final int uplinksUp;
  final int uplinksTotal;
  final int? ramMb;

  int get ponUp => pons.where((p) => p.up).length;

  /// نسبة المتّصلين ٪ — `null` بلا مشتركين (لا «0٪» كاذبة).
  double? get onlinePct => onusTotal == 0 ? null : onusOnline * 100 / onusTotal;
}
