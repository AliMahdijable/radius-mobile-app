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

/// خانات العدّ بالشرائح والنسخ: الحالات الطازجة، ثمّ ما زال يُقرأ، ثمّ ما عُرض من آخر قراءة.
enum CheckBucket { down, warn, unread, ok, statusOnly, pending, stale }

/// حال الجهاز بالتقرير — بترتيب العرض (الأسوأ أوّلاً). [statusOnly] (٩ نوفمبر): يُعرف حاله وحده (بلا بيانات دخول، علامةٌ بلا
/// مقاييس، بروتوكولٌ لا يُقرأ) — قسمٌ وحده لا «لم يُقرأ».
enum CheckState { down, warn, unread, ok, statusOnly }

enum CheckLevel { bad, warn, info }

enum CheckRole { router, switcher, sector, link, olt, other }

class CheckFinding {
  const CheckFinding(this.level, this.text);
  final CheckLevel level;
  final String text;
}

/// مشتركٌ على السكتر (محطّة بجدول تسجيله).
class CheckSub {
  const CheckSub({
    required this.name,
    this.signal,
    this.rxSignal,
    this.light,
    this.ccq,
    this.txRate,
    this.rxRate,
    this.weak = false,
    this.lowCcq = false,
    this.mac,
    this.user,
    this.approx = false,
    this.rxOnly = false,
  });
  final String name;

  /// الطراز لم يعطِ إشارة المشترك من جهتنا (tx) ⇒ [signal] هو ما نستقبله منه (rx) ويُكتب باسمه (٨ نوفمبر).
  final bool rxOnly;

  /// ماك المحطّة/الـONU (للنسخ)، ويوزر المشترك المطابق بماك جلسته — [approx] = ماكٌ قريب لا مطابق (جهاز الضوئي كثيراً ما يأخذ
  /// ماك الجلسة بفرقٍ صغير عن ماكه) — المالك ٦ نوفمبر: «او النقر عليه يفتحله اليوزر المشابه».
  final String? mac;
  final String? user;
  final bool approx;

  /// ما يُعرض: اليوزر إن عُرف، وإلّا الاسم.
  String get title => user ?? name;

  /// إشارة المشترك من جهتنا (كيف يستقبلنا) إن أعطاها الطراز، وإلّا ما نستقبله منه — وعليها الحكم.
  final int? signal;

  /// ما نستقبله منه (rx عند السكتر) — يُعرض بجانبها حين تختلفان (المالك ٦ نوفمبر: «او تظهرهن الاثنين»).
  final int? rxSignal;

  /// ONU بالأولت: ضوءها (dBm).
  final double? light;
  final int? ccq, txRate, rxRate;
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
    this.fiberRxMin = -27,
    this.voltBase = const {},
    this.voltBelow = const {},
  });

  final int cpuMax, memMax, tempMax;

  /// الوصلة (لنك/محطّة) — حدّا «القراءات الحسّاسة».
  final int linkSignalMin, linkCcqMin;

  /// محطّات السكتر — حدّا «تنبيه المشترك».
  final int subSignal, subCcq;

  /// ضوء الـONU — حدّ «تنبيه المشترك» للفايبر.
  final double fiberRxMin;

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
  const CheckMemo({this.ports = const {}, this.peers, this.role});
  final Map<String, PortMemo> ports;
  final int? peers;

  /// دوره من آخر قراءةٍ قُرئ فيها لاسلكيّه (أو لا راديو له) — يُحكم به حين لا يُقرأ اللاسلكيّ هذه المرّة ([DeviceGlance.radioUnread]).
  final CheckRole? role;

  Map<String, dynamic> toJson() => {
        if (ports.isNotEmpty) 'p': {for (final e in ports.entries) e.key: e.value.toJson()},
        if (peers != null) 'n': peers,
        if (role != null) 'r': role!.name,
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
      role: CheckRole.values.where((r) => r.name == j['r']).firstOrNull,
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
    this.signal,
    this.remoteSignal,
    this.linkCcq,
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
    this.lightsWanted,
    this.memo,
    this.pending = false,
    this.staleAt,
    this.staleFrom,
    this.staleUpTo = false,
    this.readVia,
    this.readMs,
  });

  final NetworkDevice device;
  final CheckRole role;
  final CheckState state;
  final DateTime at;
  final bool viaVpn;
  final int? ms;

  /// الوصلة: إشارتها هنا، وإشارة الطرف الثاني (كيف يستقبلنا)، وCCQ.
  final int? signal, remoteSignal, linkCcq;
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

  /// أولت: كم ONU متّصلة طُلب ضوؤها — أكثر من [subs] المقروءة ⇒ «الضوء n من N» (٩ نوفمبر).
  final int? lightsWanted;

  /// للحفظ والمقارنة بالفحص التالي.
  final CheckMemo? memo;

  /// سطرٌ مؤقّت: الجهاز تجاوز المهلة الأولى وقراءته جارية (٩ نوفمبر) — يحلّ محلّه تقريره حين تصل أو عند السقف.
  final bool pending;

  /// التقرير من **آخر قراءةٍ** لا من هذا الفحص (٩ نوفمبر — الجديدة لم تكتمل): لحظتها ومصدرها («آخر قراءة» · «فحص الخادم»).
  /// يُعرض عمرها بجانب الحال دائماً — لا يُقدَّم طازجاً.
  final DateTime? staleAt;
  final String? staleFrom;

  /// [staleAt] أقدم ما يمكن لا لحظةٌ معروفة (ملخّص أولت الخادم بلا وقته — حتى ٣٠ د): العمر «حتى 30 د» لا «قبل 30 د».
  final bool staleUpTo;

  /// «قبل 3 د» — عمر [staleAt] (أو «حتى 30 د» لعمرٍ أقصى).
  String? get staleAge => staleAt == null
      ? null
      : (staleUpTo ? 'حتى ${at.difference(staleAt!).inMinutes} د' : DevicesCheck.ago(staleAt!, at));

  /// طريق القراءة (API · SSH · الويب · SNMP · Telnet، و«عبر الـVPN») وزمنها بالمللي — يُكتبان على السطر («SSH · 18ث»).
  final String? readVia;
  final int? readMs;

  /// «SSH · 18ث» — null إن لم يُعرفا.
  String? get readLine {
    final parts = <String>[
      if (readVia != null) readVia!,
      if (readMs != null) '${readMs! < 10000 ? (readMs! / 1000).toStringAsFixed(1) : (readMs! / 1000).round()}ث',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  int get subsWeak => subs.where((s) => s.weak).length;
  int get subsLowCcq => subs.where((s) => s.lowCcq).length;
  int get subsBad => subs.where((s) => s.bad).length;
  int get portsFlagged => ports.where((p) => p.flagged).length;

  String get roleLabel => DevicesCheck.roleLabel(role, device);

  /// الحال كما تُعرض — ومن آخر قراءةٍ بعمرها («سليم · قبل 3 د»)، لا تُقدَّم طازجة.
  String get stateLabel {
    // المؤقّت (القراءة جارية) لا يُحكم بحاله المؤقّتة — «يقرأ…»، وما عُرض من آخر قراءةٍ بعمرها دائماً (المراجعة)
    if (pending) return staleAt == null ? 'يقرأ…' : 'يقرأ… · آخر قراءة $staleAge';
    final s = DevicesCheck.stateName(state);
    return staleAt == null ? s : '$s · $staleAge';
  }

  /// خانة العدّ: المؤقّت «يقرأ»، وآخر قراءةٍ «آخر قراءة»، والباقي بحاله — فلا يُعدّ القديم أو الجاري «سليماً» الآن (المراجعة).
  CheckBucket get bucket => pending
      ? CheckBucket.pending
      : staleAt != null
          ? CheckBucket.stale
          : CheckBucket.values.byName(state.name);

  /// الحيويّات كما تُعرض وتُنسخ: (العنوان، القيمة).
  List<({String k, String v})> get vitals => [
        if (signal != null) (k: 'الإشارة', v: '$signal dBm'),
        if (remoteSignal != null) (k: 'الطرف الثاني', v: '$remoteSignal dBm'),
        if (linkCcq != null && linkCcq! > 0) (k: 'CCQ', v: '$linkCcq٪'),
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
      b.write('\n  - ${s.title}${s.mac != null ? ' (${DevicesCheck.fmtMac(s.mac!)})' : ''}: ${DevicesCheck.subLine(s)}');
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
  ///
  /// [known] دوره من آخر قراءةٍ قُرئ فيها لاسلكيّه — يُحكم به حين لم يُقرأ لاسلكيّه هذه المرّة ([DeviceGlance.radioUnread]):
  /// نوع السجلّ وحده يقول «راوتر» لسكتر بيس بوكس (٩ نوفمبر).
  ///
  /// المراجعة الثانية: وضعٌ لم تقله القراءة ([DeviceGlance.apUnknown] — قراءة الخادم بلا `ap`) أو راديو مقروءٌ لا يعمل
  /// ([DeviceGlance.linkDown]) يأخذان [known] كذلك؛ وسجلٌّ «وصلة» يقرأ نقطة وصولٍ بطرفٍ واحدٍ أو بلا طرف ([peers]) يبقى وصلة —
  /// طرف الـPtP المرسل لا «سكتر» يقول «ما عليه أحد الآن» حين سقط طرفه الثاني.
  static CheckRole roleOf(NetworkDevice d, DeviceGlance? g, {CheckRole? known, int peers = 0}) {
    if (OltProfile.fromDevice(d).opensOltPanel || (g?.onusTotal ?? 0) > 0) return CheckRole.olt;
    if (g != null && (g.radioUnread || g.apUnknown || g.linkDown) && g.isAp == null && known != null) return known;
    final t = d.type.toLowerCase();
    if (t == 'link' && g?.isAp == true && peers <= 1) return CheckRole.link;
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

  /// ماكٌ بأيّ صيغة ⇒ ١٢ حرفاً ستّ‌عشريّاً صغيراً؛ غير ذلك null.
  static String? normMac(String? m) {
    final h = (m ?? '').toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    return h.length == 12 ? h : null;
  }

  /// «AA:BB:CC:DD:EE:FF» للعرض والنسخ.
  static String fmtMac(String norm) => [for (var i = 0; i < 12; i += 2) norm.substring(i, i + 2)].join(':').toUpperCase();

  /// يوزر المشترك بماك جلسته: المطابق أوّلاً، وإلّا الأقرب من الشركة نفسها (أوّل ستّة حروف) بفرقٍ ≤ ٨ — جهاز الضوئي بوضع
  /// الراوتر يأخذ للجلسة ماكاً بعد ماكه بقليل. التعادل لا يُحسم (null).
  static ({String user, bool approx})? matchMac(String? mac, Map<String, String> index) {
    final m = normMac(mac);
    if (m == null || index.isEmpty) return null;
    final exact = index[m];
    if (exact != null) return (user: exact, approx: false);
    final v = int.parse(m, radix: 16);
    final oui = m.substring(0, 6);
    String? best;
    var bestD = 9;
    var tie = false;
    for (final e in index.entries) {
      if (!e.key.startsWith(oui)) continue;
      final d = (int.parse(e.key, radix: 16) - v).abs();
      if (d < bestD) {
        bestD = d;
        best = e.value;
        tie = false;
      } else if (d == bestD && e.value != best) {
        tie = true;
      }
    }
    return best == null || tie ? null : (user: best, approx: true);
  }

  static String stateName(CheckState s) => switch (s) {
        CheckState.down => 'طافي',
        CheckState.warn => 'ملاحظات',
        CheckState.unread => 'لم يُقرأ',
        CheckState.ok => 'سليم',
        CheckState.statusOnly => 'الحال فقط',
      };

  /// «قبل لحظات» · «قبل 3 د» — عمر قراءةٍ سابقة.
  static String ago(DateTime then, DateTime now) {
    final m = now.difference(then).inMinutes;
    return m < 1 ? 'قبل لحظات' : 'قبل $m د';
  }

  static String fmtMbps(int mbps) => mbps >= 1000 && mbps % 1000 == 0 ? '${mbps ~/ 1000}G' : (mbps >= 1000 ? '${mbps / 1000}G' : '${mbps}M');

  static String subLine(CheckSub s) => [
        if (s.light != null) '${s.light!.toStringAsFixed(1)} dBm',
        // ٨ نوفمبر: كلّ رقمٍ باسمه — tx (كيف يستقبلنا المشترك) أو rx (ما نستقبله منه) — فلا يُقرأ الـrx إشارةً للمشترك
        if (s.signal != null)
          '${s.rxOnly ? 'rx' : 'tx'} ${s.signal} dBm${s.rxSignal != null && s.rxSignal != s.signal ? ' (rx ${s.rxSignal})' : ''}',
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
    Map<String, String> macUsers = const {},
    DateTime? now,
    String? readNote,
    bool pending = false,
    DateTime? staleAt,
    String? staleFrom,
    bool staleUpTo = false,
    bool statusOnly = false,
    String? readVia,
    int? readMs,
  }) {
    ({String user, bool approx})? who(String? mac) => matchMac(mac, macUsers);
    final at = now ?? DateTime.now();
    final g = detail?.glance;
    // دوره المعروف: من اللقطة، وإلّا لقطةٌ قديمة فيها مشتركون (تُحفظ للسكتر وحده)
    final known = prev?.role ?? (prev?.peers != null ? CheckRole.sector : null);
    final role = roleOf(d, g, known: known, peers: detail?.peers.length ?? 0);
    // آخر قراءةٍ لا هذا الفحص (٩ نوفمبر): لا مقارنة منافذ ولا «ما عليه أحد الآن» ولا لقطة — أرقامها بعمرها وحدها
    final stale = staleAt != null;
    final countsOnly = portsCountsOnly || stale;

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
        state: statusOnly ? CheckState.statusOnly : CheckState.unread,
        at: at,
        viaVpn: viaVpn,
        ms: ms,
        findings: [CheckFinding(CheckLevel.info, unreadReason ?? 'يردّ، لكن ما انقرت معلوماته')],
        memo: prev,
        pending: pending,
        readVia: readVia,
        readMs: readMs,
      );
    }

    final f = <CheckFinding>[
      // عن القراءة نفسها (جزئيّة، بطيئة) — معلومةٌ لا ملاحظة على الجهاز
      if (readNote != null) CheckFinding(CheckLevel.info, readNote),
    ];
    // فقدان الحزم من بنك الفحص الشامل (ثلاث حزم) — الجهاز يردّ لكنّ الطريق إليه متقطّع
    if (loss != null && loss > 0) {
      f.add(CheckFinding(loss >= 50 ? CheckLevel.bad : CheckLevel.warn, 'فقدان حزم ${loss.round()}٪ — الطريق إليه متقطّع'));
    }
    // قراءةٌ سابقة: مدّة التشغيل حتى الآن = مدّتها يومها + عمرها (لا «اشتغل قبل 2 د» عن جهازٍ اشتغل قبل 6)
    final upThen = g.linkUptime ? null : g.uptimeSec;
    final up = upThen == null || staleAt == null ? upThen : upThen + at.difference(staleAt).inSeconds;
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
    // الوصلة: إشارتها هنا وإشارة الطرف الثاني (من جدول تسجيلها) — والحكم على الأضعف. طرفها المرسل (نقطة وصولٍ مسجّلة «وصلة»)
    // لا إشارة له: طرفه الثاني محطّته الوحيدة (كيف تستقبلنا، وإلّا كيف نستقبلها) — المراجعة الثانية
    final linkAp = role == CheckRole.link && g.isAp == true;
    final one = role == CheckRole.link && detail.peers.length == 1 ? detail.peers.first : null;
    final remote = one == null ? null : (linkAp ? (one.txSignal ?? one.signal) : one.txSignal);
    // ووضعه لم يُقرأ (الخادم بلا ap، حزمة wifi) بطرفٍ واحد: إشارة صفّه بجدول التسجيل ما يستقبله هذا الجهاز من طرفه —
    // إشارتها هنا، محطّةً كان أو نقطة وصول (مراجعة 180)؛ ولا «0 dBm»
    final rx1 = g.isAp == null ? one?.signal : null;
    final here = g.signal ?? (rx1 != null && rx1 < 0 ? rx1 : null);
    // حكمٌ على الوصلة نفسها (مقطوعة أو بلا طرف) — يغني عن «إشارتها ما انقرت»
    var linkJudged = false;
    if (role == CheckRole.link) {
      if (g.linkDown) {
        f.add(const CheckFinding(CheckLevel.bad, 'الوصلة مقطوعة — لا إشارة'));
        linkJudged = true;
      } else if (linkAp && g.peersKnown && !stale && detail.peers.isEmpty && g.signal == null && g.signalPct == null) {
        // وطرفٌ يقرأ إشارة وصلته هو (ميموزا PtP: قدرة استقباله، ولا جدول محطّاتٍ له) يُحكم بها أدناه (مراجعة 180)
        f.add(const CheckFinding(CheckLevel.bad, 'الوصلة بلا طرفٍ ثانٍ'));
        linkJudged = true;
      } else {
        final worst = [here, remote].whereType<int>().fold<int?>(null, (a, b) => a == null || b < a ? b : a);
        if (worst != null && worst <= limits.linkSignalMin) {
          final far = worst == remote && remote != here ? ' (عند الطرف الثاني)' : '';
          f.add(CheckFinding(CheckLevel.warn, 'إشارة الوصلة $worst dBm — ضعيفة$far'));
        }
        if (g.ccq != null && g.ccq! > 0 && g.ccq! < limits.linkCcqMin) {
          f.add(CheckFinding(CheckLevel.warn, 'CCQ الوصلة ${g.ccq}٪ — واطي'));
        }
      }
    }

    // ── السكتر ومشتركوه ──
    var subs = <CheckSub>[];
    var subsKnown = false;
    if (role == CheckRole.sector) {
      // ٩ نوفمبر: الفراغ «ما عليه أحد» حين قُرئ جدوله فعلاً وحده — لا لأنّ الفحص من شبكتك: جدول تسجيلٍ انتهت مهلته كان يُعدّ
      // فارغاً فيقول «ما عليه أحد الآن — كانوا N». وقراءةٌ سابقة لا تقول «الآن».
      subsKnown = detail.peers.isNotEmpty || (g.peersKnown && !stale);
      subs = [
        for (final p in detail.peers)
          CheckSub(
            name: p.name,
            // المالك ٦ نوفمبر: «مفروض تقره الاشارة من عدنا وليس rx» — إشارته من جهتنا أوّلاً، والـrx بجانبها
            signal: p.txSignal ?? p.signal,
            rxSignal: p.txSignal != null ? p.signal : null,
            rxOnly: p.txSignal == null && p.signal != null,
            ccq: p.hasCcq ? p.ccq : null,
            txRate: p.txRate,
            rxRate: p.rxRate,
            weak: (p.txSignal ?? p.signal) != null && (p.txSignal ?? p.signal)! < limits.subSignal,
            lowCcq: p.hasCcq && p.ccq! <= limits.subCcq,
            mac: normMac(p.mac),
            user: who(p.mac)?.user,
            approx: who(p.mac)?.approx ?? false,
          ),
      ]..sort((a, b) {
          if (a.bad != b.bad) return a.bad ? -1 : 1;
          return (a.signal ?? 0).compareTo(b.signal ?? 0);
        });
      final w = subs.where((s) => s.weak).length;
      final l = subs.where((s) => s.lowCcq).length;
      if (w > 0 || l > 0) {
        // الرقم بعد الكلمة لا قبلها: «1 CCQ» يُرسم «CCQ 1» في سطرٍ عربيّ (لقطة ٦ نوفمبر)
        f.add(CheckFinding(
            CheckLevel.warn, '${[if (w > 0) 'إشارة ضعيفة: $w', if (l > 0) 'CCQ واطي: $l'].join(' · ')} — من ${subs.length} مشترك'));
      }
      if (g.linkDown && !stale) {
        // راديو نقطة الوصول مفعّلٌ ومقروءٌ ولا يعمل — لا «ما عليه أحد الآن» بحالٍ «سليم» (المراجعة الثانية)
        final was = prev?.peers ?? 0;
        f.add(CheckFinding(CheckLevel.bad, 'الراديو لا يعمل${was > 0 ? ' — كانوا $was بالفحص السابق' : ''}'));
      } else if (subsKnown && subs.isEmpty) {
        final was = prev?.peers ?? 0;
        f.add(was >= 3
            ? CheckFinding(CheckLevel.warn, 'ما عليه أحد الآن — كانوا $was بالفحص السابق')
            : const CheckFinding(CheckLevel.info, 'ما عليه أحد الآن'));
      } else if (!subsKnown) {
        // لا رقم ولا «لا أحد»: يُقال إنّها لم تُقرأ (والعدد السابق يبقى للمقارنة التالية)
        f.add(const CheckFinding(CheckLevel.info, 'قائمة مشتركيه ما انقرت'));
      }
    }

    // ── الأولت ──
    // قراءتنا لم يخرج منها منفذ PON ولا مشترك (فيرموير بتسمياتٍ لا يعرفها المحلّل، عرض SNMP مقيّد، منافذ الصعود
    // وحدها) ⇒ بنيته لم تُقرأ: «لم يُقرأ» لا «أولت · سليم»، ولا «ONU 0/0» (المراجعة الثالثة). ملخّص الخادم (منافذه من
    // مشتركيه، وقراءته تمّت عنده) يُحكم به كما كان
    final oltGap = role == CheckRole.olt && !detail.onuLightsServer && g.pons.isEmpty && (g.onusTotal ?? 0) == 0;
    if (oltGap) f.add(const CheckFinding(CheckLevel.info, 'منافذ PON ما انقرت'));
    if (role == CheckRole.olt) {
      final downPons = [for (final p in g.pons) if (!p.up && p.total > 0) p.label];
      if (downPons.isNotEmpty) f.add(CheckFinding(CheckLevel.warn, 'منفذ PON طافي: ${downPons.join('، ')}'));
      // ضوء كلّ ONU (المالك: «+ الاولتي… مفروض هم تظهرهن») — بحدّ «تنبيه المشترك» للفايبر. ٩ نوفمبر: الحكم من البنية، والضوء
      // جزئيٌّ إن لم يكتمل بمهلته — يُقال كم قُرئ، والضعيف يُعدّ من المقروء وحده (لا «ضوء ضعيف: 0» لما لم يُقرأ)
      final wanted = detail.onuLightsWanted;
      // ملخّص الخادم يرسل الأضعف حتى [DeviceVitals.serverLightsMax] ممّا قرأه — قائمةٌ بلغته (والمتّصل أكثر منها) ما
      // بعدها أقوى منها أو لم يُقرأ، لا «لم يقرأه الخادم» وقد قرأه (المراجعة الثالثة)
      final cut = detail.onuLightsServer &&
          detail.onuLights.length >= DeviceVitals.serverLightsMax &&
          (wanted ?? 0) > detail.onuLights.length;
      if (wanted != null && wanted > 0) {
        final read = detail.onuLights.length;
        final answered = detail.onuLightsAnswered ?? read;
        // «ما لحق» لما لم يُسأل/لم يجب بمهلته وحده، و«بلا قراءة ضوء» لما أجاب بلا قيمةٍ صالحة (المراجعة)
        if (answered < wanted) {
          // ملخّص الخادم: يقرأ بعضها ويُبقي الأضعف — «لم يقرأه الخادم» لا «ما لحق» (المراجعة الثانية)
          final srv = detail.onuLightsServer;
          f.add(CheckFinding(
              CheckLevel.info,
              read == 0
                  ? (srv ? 'ضوء المشتركين لم يقرأه الخادم' : 'ضوء المشتركين ما انقرأ هالمرّة')
                  : cut
                      ? 'الضوء: أضعف $read من $wanted — الباقي أقوى منها أو لم يقرأه الخادم'
                      : 'الضوء: قُرئ $read من $wanted — ${srv ? 'الباقي لم يقرأه الخادم' : 'الباقي ما لحق'}'));
        }
        if (answered > read) f.add(CheckFinding(CheckLevel.info, 'بلا قراءة ضوء: ${answered - read}'));
      }
      if (detail.onuLights.isNotEmpty) {
        subsKnown = true;
        subs = [
          for (final o in detail.onuLights)
            CheckSub(
              name: o.name,
              light: o.rx,
              weak: o.rx < limits.fiberRxMin,
              mac: normMac(o.mac),
              user: who(o.mac)?.user,
              approx: who(o.mac)?.approx ?? false,
            ),
        ]..sort((a, b) => a.light!.compareTo(b.light!));
        final w = subs.where((x) => x.weak).length;
        // المقطوعة: الضعيف كلّه فيها ما دام فيها غير ضعيف؛ وكلّها ضعيفة ⇒ قد يكون غيرها («300+»)
        if (w > 0) {
          final n = cut && w == subs.length ? '$w+' : '$w';
          f.add(CheckFinding(CheckLevel.warn,
              cut ? 'ضوء ضعيف: $n — من أضعف ${subs.length}' : 'ضوء ضعيف: $w — من ${subs.length} مشترك'));
        }
      }
    }

    // ── المنافذ (السويج والراوتر وكلّ ما له إيثر) ──
    // قفص SFP فارغ ليس منفذاً مستعمَلاً (٨ نوفمبر — المالك: «بالفحص الشامل اكو سكاتر يقره اسم الايثر sfp! وهو مبي sfp»):
    // بيس بوكس ونت ميتال وأخواتها يسمّيها راوتر OS ‏sfp1 وإن لم تُركَّب فيها وحدة ⇒ طافٍ دائماً بجانب الإيثر الحقيقيّ. لا يُعرض
    // ولا يُعدّ ما دام طافياً ولم يُرَ شغّالاً في فحصٍ سابق؛ الشغّال يبقى (بضوئه)، وما كان شغّالاً ثمّ طفى يبقى ليُقال «طفى».
    final phys = detail.ports.where((p) => p.physical && !_emptySfpCage(p, prev)).toList();
    final ports = <CheckPort>[];
    final memoPorts = <String, PortMemo>{};
    if (!countsOnly) {
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

    // لاسلكيّه لم يُقرأ ولراديو مفعّل (٩ نوفمبر — المراجعة): الوصلة بلا إشارتها، وما لم يُعرف دوره بلا وضعه ومشتركيه — لا «سليم».
    // المراجعة الثانية: الوصلة بلا إشارةٍ ولا جودة ولا طرفٍ ثانٍ لا تكون «سليم» أبداً (لا تحت radioUnread وحده) — إلّا وصلةٌ سلكيّة
    // قُرئت واجهاتها بلا راديو
    var radioGap = false;
    if (role == CheckRole.link) {
      if (!linkJudged && here == null && g.signalPct == null && remote == null && g.hasRadio != false) {
        f.add(const CheckFinding(CheckLevel.info, 'إشارة الوصلة ما انقرت'));
        radioGap = true;
      }
    } else if (g.radioUnread && role != CheckRole.sector && role != CheckRole.olt && role != CheckRole.switcher) {
      // السويج يُحكم بمنافذه — جدولٌ لم يُقرأ يقوله «المنافذ ما انقرت» أدناه، لا «وضعه اللاسلكيّ»
      f.add(const CheckFinding(CheckLevel.info, 'وضعه اللاسلكيّ ومشتركوه ما انقرأوا'));
      radioGap = true;
    }
    // جدول المنافذ لم يُقرأ (المراجعة الثانية): صريحاً من القارئ، أو سويج/راوتر كانت له منافذ وقراءته الجديدة بلا منفذٍ واحد —
    // «المنافذ ما انقرت» و«لم يُقرأ»، لا «سليم» بلا منافذ (واللقطة تبقى بمنافذها)
    final portsGap = g.portsUnread ||
        (!countsOnly &&
            phys.isEmpty &&
            (role == CheckRole.switcher || role == CheckRole.router) &&
            (prev?.ports.isNotEmpty ?? false));
    if (portsGap) f.add(const CheckFinding(CheckLevel.info, 'المنافذ ما انقرت'));

    // «سليم» للسكتر حكمٌ عليه وعلى مشتركيه — قائمتهم لم تُقرأ ⇒ «لم يُقرأ» بحيويّاته وسطرها، لا «سليم» (٩ نوفمبر)
    final state = f.any((x) => x.level != CheckLevel.info)
        ? CheckState.warn
        : ((role == CheckRole.sector && !subsKnown) || radioGap || portsGap || oltGap
            ? CheckState.unread
            : CheckState.ok);
    return DeviceCheckReport(
      device: d,
      role: role,
      state: state,
      at: at,
      viaVpn: viaVpn,
      ms: ms,
      signal: role == CheckRole.link ? here : null,
      remoteSignal: remote,
      linkCcq: role == CheckRole.link ? g.ccq : null,
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
      onusOnline: oltGap ? null : g.onusOnline,
      onusTotal: oltGap ? null : g.onusTotal,
      lightsWanted: role == CheckRole.olt ? detail.onuLightsWanted : null,
      pending: pending,
      staleAt: staleAt,
      staleFrom: staleFrom,
      staleUpTo: staleUpTo,
      readVia: stale ? null : readVia,
      readMs: stale ? null : readMs,
      // قراءةٌ سابقة لا تكتب اللقطة — المقارنة التالية بما قُرئ فعلاً
      memo: stale
          ? prev
          : CheckMemo(
              // قراءةٌ بلا منافذ (طبقة SNMP الأولى مثلاً) لا تمحو منافذ اللقطة — «طفى» التالية تبقى ممكنة
              ports: countsOnly || phys.isEmpty ? (prev?.ports ?? const {}) : memoPorts,
              peers: role == CheckRole.sector && subsKnown ? subs.length : prev?.peers,
              // الدور يُحفظ حين قُرئ لاسلكيّه (أو لا راديو له) — لا من نوع السجلّ وقت الجهل
              role: (g.radioUnread || g.apUnknown || g.linkDown) && g.isAp == null ? prev?.role : role,
            ),
    );
  }

  static final _sfpName = RegExp(r'^(q?sfp)', caseSensitive: false);

  /// قفص SFP طافٍ لم يُرَ شغّالاً في الفحص السابق — بلا وحدةٍ غالباً (انظر المنافذ أعلاه).
  static bool _emptySfpCage(PortTraffic p, CheckMemo? prev) =>
      !p.up && _sfpName.hasMatch(p.name.trim()) && prev?.ports[p.name]?.up != true;

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
  /// اسم خانة العدّ كما تُعرض وتُنسخ.
  static String bucketName(CheckBucket b) => switch (b) {
        CheckBucket.pending => 'يقرأ',
        CheckBucket.stale => 'آخر قراءة',
        _ => stateName(CheckState.values.byName(b.name)),
      };

  /// التقرير كلّه نصّاً. [progress] أثناء الفحص: «لم يكتمل — n من N» (من لم يبدأ بعد لا يغيب بصمت).
  static String reportText(List<DeviceCheckReport> rs, {required bool viaVpn, DateTime? at, ({int done, int total})? progress}) {
    final c = {for (final b in CheckBucket.values) b: rs.where((r) => r.bucket == b).length};
    String part(CheckBucket b) => '${bucketName(b)} ${c[b]}';
    final head = 'الفحص الشامل — ${rs.length} جهاز${viaVpn ? ' (عبر الـVPN)' : ''}: '
        '${[
      for (final b in [CheckBucket.down, CheckBucket.warn, CheckBucket.unread])
        if (c[b]! > 0) part(b),
      part(CheckBucket.ok),
      for (final b in [CheckBucket.statusOnly, CheckBucket.pending, CheckBucket.stale])
        if (c[b]! > 0) part(b),
    ].join(' · ')}'
        '${progress != null && progress.done < progress.total ? ' — لم يكتمل: ${progress.done} من ${progress.total}' : ''}';
    return [head, for (final r in sorted(rs)) r.toText()].join('\n\n');
  }
}
