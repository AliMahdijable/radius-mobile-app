// «الفحص الشامل» لقسم الأجهزة — المقيِّم النقيّ (بلا شبكة): قراءة جهازٍ واحد ⇒ تقريره المنفصل.
//
// المالك ٦ نوفمبر: «قسم الاجهزه يجب ان نضيف فحص عام بي كذلك ويخضع لل vpn» ثمّ «من يكون الجهاز ع شكل سكتر يفحص الجهاز نفسه
// ويفحص المشتركين الي بداخلة ويعطي تقرير منفصل لكل جهاز» ثمّ «كذلك السوجات من حيث المتغيرات الحيوية فكر بيها بدقة».
//
// الجلب (من شبكتك أو عبر الـVPN) في [DevicesCheckRunner] (devices_check_runner.dart)، والعرض في DevicesCheckScreen.
// الحدود من الوكيل نفسه: «القراءات الحسّاسة» (المعالج/الحرارة/الوصلة + الكهرباء بمعدّل كلّ جهاز) و«تنبيه المشترك» (إشارة المحطّة وCCQ).
import 'dart:math' as math;

import '../api/mikrotik_api.dart';
import '../api/olt_profile.dart';
import '../models/network_device.dart';
import '../screens/network_devices/device_vitals.dart';

/// حال الجهاز بالتقرير — بترتيب العرض (الأسوأ أوّلاً).
enum CheckState { down, warn, unread, ok }

enum CheckLevel { bad, warn, info }

enum CheckRole { router, switcher, sector, link, olt, other }

class CheckFinding {
  const CheckFinding(this.level, this.text);
  final CheckLevel level;
  final String text;
}

/// مشتركٌ على السكتر (محطّة بجدول تسجيله).
class CheckSub {
  const CheckSub({required this.name, this.signal, this.ccq, this.txRate, this.rxRate, this.weak = false, this.lowCcq = false});
  final String name;
  final int? signal, ccq, txRate, rxRate;
  final bool weak, lowCcq;
  bool get bad => weak || lowCcq;
}

/// منفذٌ سلكيّ فعليّ وملاحظاته.
class CheckPort {
  const CheckPort({required this.name, required this.up, this.speed, this.notes = const [], this.level});
  final String name;
  final bool up;
  final String? speed;
  final List<String> notes;

  /// أسوأ ملاحظاته (null = بلا ملاحظة).
  final CheckLevel? level;
  bool get flagged => notes.isNotEmpty;
}

/// الحدود — من إعدادات الوكيل (وإلّا افتراضات الخادم نفسها).
class CheckLimits {
  const CheckLimits({
    this.cpuMax = 90,
    this.memMax = 90,
    this.tempMax = 80,
    this.linkSignalMin = -80,
    this.linkCcqMin = 50,
    this.subSignal = -60,
    this.subCcq = 50,
    this.voltBase = const {},
    this.voltBelow = const {},
  });

  final int cpuMax, memMax, tempMax;

  /// الوصلة (لنك/محطّة) — حدّا «القراءات الحسّاسة».
  final int linkSignalMin, linkCcqMin;

  /// محطّات السكتر — حدّا «تنبيه المشترك».
  final int subSignal, subCcq;

  /// الكهرباء: معدّل كلّ جهاز وحدّ تنبيهه (بمعرّفه) من «تنبيهات أجهزتي».
  final Map<int, double> voltBase, voltBelow;
}

/// ما يُحفظ من الفحص للمقارنة بالتالي: المنافذ وعدد المتّصلين.
class PortMemo {
  const PortMemo({required this.up, this.mbps, this.linkDowns, this.errors});
  final bool up;
  final int? mbps, linkDowns, errors;

  Map<String, dynamic> toJson() => {'u': up, if (mbps != null) 's': mbps, if (linkDowns != null) 'l': linkDowns, if (errors != null) 'e': errors};

  static PortMemo? fromJson(Object? j) {
    if (j is! Map) return null;
    int? n(Object? x) => x is num ? x.toInt() : null;
    return PortMemo(up: j['u'] == true, mbps: n(j['s']), linkDowns: n(j['l']), errors: n(j['e']));
  }
}

class CheckMemo {
  const CheckMemo({this.ports = const {}, this.peers});
  final Map<String, PortMemo> ports;
  final int? peers;

  Map<String, dynamic> toJson() => {
        if (ports.isNotEmpty) 'p': {for (final e in ports.entries) e.key: e.value.toJson()},
        if (peers != null) 'n': peers,
      };

  static CheckMemo? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['p'];
    return CheckMemo(
      ports: {
        if (p is Map)
          for (final e in p.entries)
            if (PortMemo.fromJson(e.value) case final m?) '${e.key}': m,
      },
      peers: j['n'] is num ? (j['n'] as num).toInt() : null,
    );
  }
}

/// تقرير جهازٍ واحد.
class DeviceCheckReport {
  const DeviceCheckReport({
    required this.device,
    required this.role,
    required this.state,
    required this.at,
    this.viaVpn = false,
    this.ms,
    this.cpu,
    this.mem,
    this.temp,
    this.volt,
    this.voltBase,
    this.uptimeSec,
    this.ppp,
    this.poeWatts,
    this.findings = const [],
    this.subs = const [],
    this.subsKnown = false,
    this.ports = const [],
    this.portsUp,
    this.portsTotal,
    this.onusOnline,
    this.onusTotal,
    this.memo,
  });

  final NetworkDevice device;
  final CheckRole role;
  final CheckState state;
  final DateTime at;
  final bool viaVpn;
  final int? ms;
  final int? cpu, mem, temp, uptimeSec, ppp;
  final double? volt, voltBase, poeWatts;
  final List<CheckFinding> findings;

  /// المشتركون على السكتر (المشاكل أوّلاً ثمّ الأضعف)؛ [subsKnown] = قُرئ جدوله فعلاً (الفارغ «ما عليه أحد» لا «لا نعرف»).
  final List<CheckSub> subs;
  final bool subsKnown;

  /// المنافذ الفعليّة (ذات الملاحظة أوّلاً)؛ عبر الـVPN بلا تفصيلٍ = الأعداد وحدها.
  final List<CheckPort> ports;
  final int? portsUp, portsTotal;
  final int? onusOnline, onusTotal;

  /// للحفظ والمقارنة بالفحص التالي.
  final CheckMemo? memo;

  int get subsWeak => subs.where((s) => s.weak).length;
  int get subsLowCcq => subs.where((s) => s.lowCcq).length;
  int get subsBad => subs.where((s) => s.bad).length;
  int get portsFlagged => ports.where((p) => p.flagged).length;

  String get roleLabel => DevicesCheck.roleLabel(role, device);

  String get stateLabel => switch (state) {
        CheckState.down => 'طافي',
        CheckState.warn => 'ملاحظات',
        CheckState.unread => 'لم يُقرأ',
        CheckState.ok => 'سليم',
      };

  /// الحيويّات كما تُعرض وتُنسخ: (العنوان، القيمة).
  List<({String k, String v})> get vitals => [
        if (cpu != null) (k: 'المعالج', v: '$cpu٪'),
        if (mem != null) (k: 'الذاكرة', v: '$mem٪'),
        if (temp != null) (k: 'الحرارة', v: '$temp°'),
        if (volt != null) (k: 'الكهرباء', v: '${volt!.toStringAsFixed(1)}V'),
        if (uptimeSec != null) (k: 'يعمل منذ', v: DeviceVitals.fmtUptime(uptimeSec!)),
        if (ppp != null) (k: 'جلسات PPP', v: '$ppp'),
        if (poeWatts != null && poeWatts! > 0) (k: 'PoE', v: '${poeWatts!.toStringAsFixed(1)}W'),
        if (portsTotal != null && portsTotal! > 0) (k: 'المنافذ', v: '${portsUp ?? 0}/$portsTotal'),
        if (onusTotal != null) (k: 'ONU', v: '${onusOnline ?? 0}/$onusTotal'),
        if (ms != null && state != CheckState.down) (k: 'الاستجابة', v: '$ms ms'),
      ];

  /// تقرير الجهاز نصّاً (للنسخ/الإرسال لفنّي).
  String toText() {
    final b = StringBuffer('${device.name} ($roleLabel) — $stateLabel');
    final v = vitals;
    if (v.isNotEmpty) b.write('\n${v.map((e) => '${e.k} ${e.v}').join(' · ')}');
    for (final f in findings) {
      b.write('\n• ${f.text}');
    }
    for (final s in subs.where((s) => s.bad)) {
      b.write('\n  - ${s.name}: ${DevicesCheck.subLine(s)}');
    }
    for (final p in ports.where((p) => p.flagged)) {
      b.write('\n  - ${p.name}: ${p.notes.join('، ')}');
    }
    return b.toString();
  }
}

class DevicesCheck {
  DevicesCheck._();

  static String roleLabel(CheckRole r, NetworkDevice d) => switch (r) {
        CheckRole.router => 'راوتر',
        CheckRole.switcher => 'سويج',
        CheckRole.sector => 'سكتر',
        CheckRole.link => 'وصلة',
        CheckRole.olt => 'أولت',
        CheckRole.other => NetworkDeviceLabels.typeLabel(d.type),
      };

  /// دور الجهاز: الأولت من علامته/لقطته، والسكتر من وضعه اللاسلكيّ (نقطة وصول) أو نوعه، والوصلة محطّةٌ لاسلكيّة.
  static CheckRole roleOf(NetworkDevice d, DeviceGlance? g) {
    if (OltProfile.fromDevice(d).opensOltPanel || (g?.onusTotal ?? 0) > 0) return CheckRole.olt;
    final t = d.type.toLowerCase();
    if (g?.isAp == true || t == 'sector' || t == 'ap') return CheckRole.sector;
    if (t == 'link' || g?.isAp == false) return CheckRole.link;
    if (t == 'switch') return CheckRole.switcher;
    if (t == 'router') return CheckRole.router;
    return CheckRole.other;
  }

  /// «1Gbps» · «100Mbps» · «2.5G» · «1000» ⇒ ميغابت؛ ما لا يُفهم null.
  static int? mbpsOf(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    final m = RegExp(r'^([0-9]+(?:\.[0-9]+)?)\s*([gmk]?)').firstMatch(t);
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!);
    if (v == null || v <= 0) return null;
    return switch (m.group(2)) {
      'g' => (v * 1000).round(),
      'k' => (v / 1000).round(),
      'm' => v.round(),
      _ => v >= 1e6 ? (v / 1e6).round() : v.round(), // رقمٌ عارٍ: بت/ث كبيرٌ أو ميغابت
    };
  }

  static String fmtMbps(int mbps) => mbps >= 1000 && mbps % 1000 == 0 ? '${mbps ~/ 1000}G' : (mbps >= 1000 ? '${mbps / 1000}G' : '${mbps}M');

  static String subLine(CheckSub s) => [
        if (s.signal != null) '${s.signal} dBm',
        if (s.ccq != null && s.ccq! > 0) 'CCQ ${s.ccq}٪',
        if (s.rxRate != null || s.txRate != null) '↓${s.rxRate ?? '—'} ↑${s.txRate ?? '—'} Mbps',
      ].join(' · ');

  static String _minutes(int sec) {
    final m = (sec / 60).floor();
    return m < 1 ? 'لحظات' : '$m د';
  }

  static String _days(double d) => d < 1.5 ? 'يوم' : '${d.round()} يوم';

  static CheckLevel? _worst(Iterable<CheckLevel> ls) {
    CheckLevel? w;
    for (final l in ls) {
      if (w == null || l.index < w.index) w = l;
    }
    return w;
  }

  /// قراءة جهازٍ واحد ⇒ تقريره. [alive] من البنك/الـVPN؛ [detail] من [DeviceVitals.fetch] (محلّيّاً) أو [DeviceVitals.fromVpn]؛
  /// [raw] لقطة المصنّع (مايكروتك: المراوح والمزوّدات)؛ [prev] من الفحص السابق؛ [portsCountsOnly] = منافذ الـVPN أعدادٌ لا أسماء.
  static DeviceCheckReport evaluate({
    required NetworkDevice d,
    required bool? alive,
    int? ms,
    double? loss,
    DeviceDetail? detail,
    Object? raw,
    String? unreadReason,
    CheckLimits limits = const CheckLimits(),
    CheckMemo? prev,
    bool viaVpn = false,
    bool portsCountsOnly = false,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final g = detail?.glance;
    final role = roleOf(d, g);

    if (alive == false) {
      final since = d.lastStatus == 'offline' ? NetworkDeviceLabels.since(d.statusSince, now: at) : null;
      return DeviceCheckReport(
        device: d,
        role: role,
        state: CheckState.down,
        at: at,
        viaVpn: viaVpn,
        findings: [CheckFinding(CheckLevel.bad, since == null ? 'لا يستجيب' : 'لا يستجيب $since')],
        memo: prev,
      );
    }
    if (detail == null || g == null) {
      return DeviceCheckReport(
        device: d,
        role: role,
        state: CheckState.unread,
        at: at,
        viaVpn: viaVpn,
        ms: ms,
        findings: [CheckFinding(CheckLevel.info, unreadReason ?? 'يردّ، لكن ما انقرت معلوماته')],
        memo: prev,
      );
    }

    final f = <CheckFinding>[];
    // فقدان الحزم من بنك الفحص الشامل (ثلاث حزم) — الجهاز يردّ لكنّ الطريق إليه متقطّع
    if (loss != null && loss > 0) {
      f.add(CheckFinding(loss >= 50 ? CheckLevel.bad : CheckLevel.warn, 'فقدان حزم ${loss.round()}٪ — الطريق إليه متقطّع'));
    }
    final up = g.linkUptime ? null : g.uptimeSec;
    final upDays = up == null ? null : up / 86400;

    // ── الجهاز نفسه ──
    if (g.cpu != null && g.cpu! >= limits.cpuMax) f.add(CheckFinding(CheckLevel.warn, 'المعالج ${g.cpu}٪ — عالي'));
    if (g.mem != null && g.mem! >= limits.memMax) f.add(CheckFinding(CheckLevel.warn, 'الذاكرة ${g.mem}٪ — شبه ممتلئة'));
    if (g.temp != null && g.temp! >= limits.tempMax) {
      f.add(CheckFinding(g.temp! >= limits.tempMax + 10 ? CheckLevel.bad : CheckLevel.warn, 'الحرارة ${g.temp}° — عالية'));
    }
    final base = limits.voltBase[d.id];
    final below = limits.voltBelow[d.id];
    if (g.voltage != null && below != null && g.voltage! < below) {
      f.add(CheckFinding(CheckLevel.bad,
          'الكهرباء ${g.voltage!.toStringAsFixed(1)}V — ${base == null ? 'تحت حدّها' : 'طبيعيّها ${base.toStringAsFixed(1)}V'}'));
    }
    if (up != null && up < 15 * 60) {
      f.add(CheckFinding(CheckLevel.warn, 'اشتغل قبل ${_minutes(up)} — انطفى أو أُعيد تشغيله'));
    }
    if (raw is MikrotikStats) {
      for (final fan in raw.fans) {
        // RPM صفر وحده ليس عطلاً (وضع auto يوقفها والجهاز بارد) — إلّا والحرارة عالية؛ حال fail صريح عطل.
        if (fan.isOk == false) {
          f.add(CheckFinding(CheckLevel.bad, 'المروحة ${fan.name} عاطلة'));
        } else if (fan.intValue == 0 && (g.temp ?? 0) >= 65) {
          f.add(CheckFinding(CheckLevel.warn, 'المروحة ${fan.name} واقفة والحرارة ${g.temp}°'));
        }
      }
      for (final p in raw.psus) {
        if (p.isOk == false) f.add(CheckFinding(CheckLevel.info, 'مزوّد الكهرباء ${p.name} لا يعمل — إن كان موصولاً فافحصه'));
      }
    }

    // ── الوصلة ──
    if (role == CheckRole.link) {
      if (g.signal != null && g.signal! <= limits.linkSignalMin) {
        f.add(CheckFinding(CheckLevel.warn, 'إشارة الوصلة ${g.signal} dBm — ضعيفة'));
      }
      if (g.ccq != null && g.ccq! > 0 && g.ccq! < limits.linkCcqMin) {
        f.add(CheckFinding(CheckLevel.warn, 'CCQ الوصلة ${g.ccq}٪ — واطي'));
      }
    }

    // ── السكتر ومشتركوه ──
    var subs = <CheckSub>[];
    var subsKnown = false;
    if (role == CheckRole.sector) {
      subsKnown = detail.peers.isNotEmpty || g.peersKnown || !viaVpn;
      subs = [
        for (final p in detail.peers)
          CheckSub(
            name: p.name,
            signal: p.signal,
            ccq: p.hasCcq ? p.ccq : null,
            txRate: p.txRate,
            rxRate: p.rxRate,
            weak: p.signal != null && p.signal! < limits.subSignal,
            lowCcq: p.hasCcq && p.ccq! <= limits.subCcq,
          ),
      ]..sort((a, b) {
          if (a.bad != b.bad) return a.bad ? -1 : 1;
          return (a.signal ?? 0).compareTo(b.signal ?? 0);
        });
      final w = subs.where((s) => s.weak).length;
      final l = subs.where((s) => s.lowCcq).length;
      if (w > 0 || l > 0) {
        f.add(CheckFinding(
            CheckLevel.warn, '${[if (w > 0) '$w إشارة ضعيفة', if (l > 0) '$l CCQ واطي'].join(' · ')} — من ${subs.length} مشترك'));
      }
      if (subsKnown && subs.isEmpty) {
        final was = prev?.peers ?? 0;
        f.add(was >= 3
            ? CheckFinding(CheckLevel.warn, 'ما عليه أحد الآن — كانوا $was بالفحص السابق')
            : const CheckFinding(CheckLevel.info, 'ما عليه أحد الآن'));
      }
    }

    // ── الأولت ──
    if (role == CheckRole.olt) {
      final downPons = [for (final p in g.pons) if (!p.up && p.total > 0) p.label];
      if (downPons.isNotEmpty) f.add(CheckFinding(CheckLevel.warn, 'منفذ PON طافي: ${downPons.join('، ')}'));
    }

    // ── المنافذ (السويج والراوتر وكلّ ما له إيثر) ──
    final phys = detail.ports.where((p) => p.physical).toList();
    final ports = <CheckPort>[];
    final memoPorts = <String, PortMemo>{};
    if (!portsCountsOnly) {
      for (final p in phys) {
        final notes = <(CheckLevel, String)>[];
        final mb = mbpsOf(p.linkSpeed);
        final was = prev?.ports[p.name];
        if (!p.up) {
          if (was?.up == true) notes.add((CheckLevel.warn, 'طفى من الفحص السابق'));
        } else {
          if (mb != null && mb <= 10) {
            notes.add((CheckLevel.warn, 'يشتغل ${p.linkSpeed} — كيبل أو كونكتر'));
          } else if (mb != null && (was?.mbps ?? 0) >= 1000 && mb < was!.mbps!) {
            notes.add((CheckLevel.warn, 'نزل من ${fmtMbps(was.mbps!)} إلى ${fmtMbps(mb)} — كيبل أو كونكتر'));
          }
          if (p.halfDuplex) notes.add((CheckLevel.warn, 'half-duplex — كيبل أو إعداد'));
          final sfp = p.sfpRx;
          if (sfp != null && sfp < -25) {
            notes.add((sfp < -30 ? CheckLevel.bad : CheckLevel.warn, 'ضوء الـSFP ${sfp.toStringAsFixed(1)} dBm — ضعيف'));
          }
        }
        final ld = p.linkDowns;
        if (ld != null) {
          final wasLd = was?.linkDowns;
          if (wasLd != null && ld >= wasLd) {
            if (ld - wasLd >= 2) notes.add((CheckLevel.warn, 'انقطع ${ld - wasLd} مرّة من الفحص السابق'));
          } else if (upDays != null && ld >= 5 && ld / math.max(upDays, 1) >= 2) {
            notes.add((CheckLevel.warn, 'انقطع $ld مرّة خلال ${_days(upDays)} — كيبل مرخي أو كهرباء الطرف الثاني'));
          }
        }
        final er = p.errors;
        if (er != null) {
          final wasEr = was?.errors;
          if (wasEr != null && er >= wasEr) {
            if (er - wasEr >= 20) notes.add((CheckLevel.warn, 'أخطاء +${er - wasEr} من الفحص السابق — كيبل تالف أو تشويش'));
          } else if (upDays != null && er >= 100 && er / math.max(upDays, 1) >= 100) {
            notes.add((CheckLevel.warn, 'أخطاء $er — كيبل تالف أو تشويش'));
          }
        }
        switch (p.poeStatus) {
          case 'short-circuit':
            notes.add((CheckLevel.bad, 'PoE: قصر — الكيبل أو الجهاز'));
          case 'overload':
            notes.add((CheckLevel.bad, 'PoE: حمل زائد'));
          case 'voltage-too-low':
            notes.add((CheckLevel.bad, 'PoE: فولتيّة واطية'));
        }
        ports.add(CheckPort(
          name: p.name,
          up: p.up,
          speed: p.linkSpeed,
          notes: [for (final n in notes) n.$2],
          level: _worst(notes.map((n) => n.$1)),
        ));
        memoPorts[p.name] = PortMemo(up: p.up, mbps: mb, linkDowns: p.linkDowns, errors: p.errors);
      }
      ports.sort((a, b) {
        if (a.flagged != b.flagged) return a.flagged ? -1 : 1;
        return 0;
      });
      final flagged = ports.where((p) => p.flagged).toList();
      if (flagged.isNotEmpty) {
        f.add(CheckFinding(_worst(flagged.map((p) => p.level!))!,
            flagged.length == 1 ? 'المنفذ ${flagged.first.name}: ${flagged.first.notes.join('، ')}' : 'منافذ فيها ملاحظات: ${flagged.length}'));
      }
    }

    final state = f.any((x) => x.level != CheckLevel.info) ? CheckState.warn : CheckState.ok;
    return DeviceCheckReport(
      device: d,
      role: role,
      state: state,
      at: at,
      viaVpn: viaVpn,
      ms: ms,
      cpu: g.cpu,
      mem: g.mem,
      temp: g.temp,
      volt: g.voltage,
      voltBase: base,
      uptimeSec: up,
      ppp: g.ppp,
      poeWatts: g.poeWatts,
      findings: f..sort((a, b) => a.level.index.compareTo(b.level.index)),
      subs: subs,
      subsKnown: subsKnown,
      ports: ports,
      portsUp: phys.isEmpty ? null : phys.where((p) => p.up).length,
      portsTotal: phys.isEmpty ? null : phys.length,
      onusOnline: g.onusOnline,
      onusTotal: g.onusTotal,
      memo: CheckMemo(
        ports: portsCountsOnly ? (prev?.ports ?? const {}) : memoPorts,
        peers: role == CheckRole.sector && subsKnown ? subs.length : prev?.peers,
      ),
    );
  }

  /// ترتيب العرض: طافي ⇒ ملاحظات ⇒ لم يُقرأ ⇒ سليم، ثمّ الأكثر ملاحظاتٍ، ثمّ الاسم.
  static List<DeviceCheckReport> sorted(Iterable<DeviceCheckReport> rs) => rs.toList()
    ..sort((a, b) {
      final s = a.state.index.compareTo(b.state.index);
      if (s != 0) return s;
      final n = b.findings.length.compareTo(a.findings.length);
      if (n != 0) return n;
      return a.device.name.compareTo(b.device.name);
    });

  /// التقرير كلّه نصّاً.
  static String reportText(List<DeviceCheckReport> rs, {required bool viaVpn, DateTime? at}) {
    final c = {for (final s in CheckState.values) s: rs.where((r) => r.state == s).length};
    final head = 'الفحص الشامل — ${rs.length} جهاز${viaVpn ? ' (عبر الـVPN)' : ''}: '
        '${[
      if (c[CheckState.down]! > 0) 'طافي ${c[CheckState.down]}',
      if (c[CheckState.warn]! > 0) 'ملاحظات ${c[CheckState.warn]}',
      if (c[CheckState.unread]! > 0) 'لم يُقرأ ${c[CheckState.unread]}',
      'سليم ${c[CheckState.ok]}',
    ].join(' · ')}';
    return [head, for (final r in sorted(rs)) r.toText()].join('\n\n');
  }
}
