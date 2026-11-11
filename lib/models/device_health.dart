/// Device kind a probe resolved against. Used by the snapshot below
/// so the card can render kind-specific metric rows.
enum DeviceKind { ont, ubiquiti, other }

DeviceKind? deviceKindFromString(String? s) {
  switch (s?.toLowerCase()) {
    case 'ont':
      return DeviceKind.ont;
    case 'ubiquiti':
      return DeviceKind.ubiquiti;
    case 'other':
      return DeviceKind.other;
    default:
      return null;
  }
}

String deviceKindToString(DeviceKind k) {
  switch (k) {
    case DeviceKind.ont:
      return 'ont';
    case DeviceKind.ubiquiti:
      return 'ubiquiti';
    case DeviceKind.other:
      return 'other';
  }
}

/// Optical metrics from a Huawei ONT — direct port of v1's OntOpticalInfo.
class OntOpticalInfo {
  const OntOpticalInfo({
    required this.txPower,
    required this.rxPower,
    required this.voltage,
    required this.temperature,
    required this.bias,
    required this.sendStatus,
    this.vendor = 'huawei',
    this.model = '',
  });
  final String txPower;
  final String rxPower;
  final String voltage;
  final String temperature;
  final String bias;
  final String sendStatus;

  /// المورّد: `huawei` (الأصل) أو `zte` (ZXIC MH80، ٢٥ أكتوبر) — يحدّد جلسة الترافيك وتوفّر إعادة التشغيل.
  final String vendor;

  /// الطراز كما يسمّيه الجهاز (ZTE: عنوان الصفحة «MH80») — فارغٌ حين لا يُعرف.
  final String model;

  bool get isZte => vendor == 'zte';

  bool get txOk {
    final v = double.tryParse(txPower);
    return v != null && v >= 0.5 && v <= 5.0;
  }

  bool get rxOk {
    final v = double.tryParse(rxPower);
    return v != null && v >= -27.0 && v <= -3.0;
  }

  bool get voltageOk {
    final v = double.tryParse(voltage);
    return v != null && v >= 3100 && v <= 3500;
  }

  bool get biasOk {
    final v = double.tryParse(bias);
    return v != null && v >= 0 && v <= 90;
  }

  bool get tempOk {
    final v = double.tryParse(temperature);
    return v != null && v >= -10 && v <= 85;
  }

  Map<String, dynamic> toJson() => {
        'tx': txPower,
        'rx': rxPower,
        'v': voltage,
        't': temperature,
        'b': bias,
        's': sendStatus,
        if (vendor != 'huawei') 'vd': vendor,
        if (model.isNotEmpty) 'md': model,
      };

  /// مخزَّنٌ قبل حقل المورّد ⇒ هواوي كما كان.
  static OntOpticalInfo fromJson(Map<String, dynamic> j) => OntOpticalInfo(
        txPower: (j['tx'] ?? '').toString(),
        rxPower: (j['rx'] ?? '').toString(),
        voltage: (j['v'] ?? '').toString(),
        temperature: (j['t'] ?? '').toString(),
        bias: (j['b'] ?? '').toString(),
        sendStatus: (j['s'] ?? '').toString(),
        vendor: (j['vd'] ?? 'huawei').toString(),
        model: (j['md'] ?? '').toString(),
      );
}

class OntLoginResult {
  const OntLoginResult({required this.sessionCookie, required this.baseUrl});
  final String sessionCookie;
  final String baseUrl;
}

/// Ubiquiti LAN port (one row per eth interface in the airOS json).
class LanPort {
  const LanPort(
      {required this.name, required this.speed, required this.plugged});
  final String name;
  final String? speed;
  final bool plugged;

  /// موصولٌ والسرعة مجهولة — لا يُصدّرها كلّ جهاز (airOS 5 مثلاً
  /// يعطي `lan_state="ON"` ولا شيء غيرها).
  bool get speedUnknown => plugged && (speed == null || speed!.isEmpty);

  String get displaySpeed {
    if (!plugged) return 'Unplugged';
    // 🐛 كان «موصولٌ بلا سرعة» يُعرَض «Unplugged» — معلومةٌ **معكوسة**
    // تُرسل الفنّيّ إلى السطح والكبل بخير. والفرق بين «لا أعرف سرعته»
    // و«مفصول» هو الفرق بين إجراءين مختلفين تماماً.
    if (speedUnknown) return 'متّصل';
    final s = speed;
    if (s == null || s == '0Mbps' || s.startsWith('0')) return 'Unplugged';
    if (s.contains('1000')) return '1 Gbps';
    final m = RegExp(r'(\d+)Mbps').firstMatch(s);
    if (m != null) return '${m.group(1)} Mbps';
    return s;
  }

  String get label => name.toUpperCase();

  Map<String, dynamic> toJson() => {
        'n': name,
        's': speed,
        'p': plugged ? 1 : 0,
      };

  static LanPort fromJson(Map<String, dynamic> j) => LanPort(
        name: (j['n'] ?? '').toString(),
        speed: j['s']?.toString(),
        plugged: (j['p'] ?? 0) == 1,
      );
}

/// Unified snapshot the UI consumes — same shape regardless of kind.
class UbiquitiStatus {
  const UbiquitiStatus({
    required this.hostname,
    required this.firmware,
    required this.uptimeSeconds,
    required this.ssid,
    required this.mode,
    required this.signalDbm,
    required this.noiseFloorDbm,
    required this.ccqPercent,
    required this.distanceMeters,
    required this.txRateKbps,
    required this.rxRateKbps,
    this.rxBytes,
    this.txBytes,
    required this.lanPorts,
    required this.peerMac,
    required this.peerCount,
    required this.baseUrl,
    this.vendor = 'ubnt',
    this.model = '',
    this.wanOnlineSeconds,
    this.dhcpCount,
    this.wanType = '',
  });

  /// المورّد: `ubnt` (الأصل — airOS) أو `tplink` (TP-Link Pharos: CPE/WBS، ١٠ نوفمبر) أو `tpclassic` (راوتر TP-Link المنزليّ
  /// القديم — TL-WR741ND وأخواته، ١١ نوفمبر) — نفس القراءات والبطاقات، ويحدّد جلسة الترافيك وتوفّر إعادة التشغيل وتسمية الجهاز.
  final String vendor;

  /// الطراز كما يسمّيه الجهاز («CPE610 v2.0») — فارغٌ حين لا يُعرف (airOS يضعه في [firmware] أو لا يذكره).
  final String model;

  bool get isTplink => vendor == 'tplink';

  /// راوتر TP-Link المنزليّ القديم (واجهة userRpm بمصادقة HTTP Basic): لا رابط لاسلكيّ للمزوّد (لا إشارة ولا CCQ)، و[peerCount]
  /// = أجهزة الوايرلس المتّصلة **الآن** (صفحة Wireless Statistics — لا إيجارات DHCP)، ولا حالة منافذ يصدّرها.
  bool get isTpClassic => vendor == 'tpclassic';

  /// راوتر TP-Link الحديث «Agile» (Archer AX10 & kin — واجهة SPA، دخول RSA+AES، ١١ نوفمبر): كذلك راوترٌ منزليّ، [peerCount] من
  /// قائمتَي الأجهزة اللاسلكيّة والسلكيّة، ومدّة الاتصال من WAN.
  bool get isTpAgile => vendor == 'tpagile';

  /// جهاز المشترك راوترٌ منزليّ (لا راديو) — ما يُعرض له يختلف: المتّصلون ومدّة الاتصال لا الإشارة والمنافذ.
  bool get isRouter => isTpClassic || isTpAgile;

  /// مدّة اتّصال الإنترنت (PPPoE) بالثواني كما يعدّها الراوتر («Online Time») — غير [uptimeSeconds] (تشغيل الجهاز). null = غير معروفة.
  final int? wanOnlineSeconds;

  /// عدد إيجارات DHCP (سلكيّ + لاسلكيّ) — ثانويّ: الإيجار يبقى بعد خروج الجهاز، فلا يُعرض «متّصلاً الآن».
  final int? dhcpCount;

  /// نوع اتّصال الإنترنت كما يسمّيه الراوتر («PPPoE»، «Dynamic IP»…) — فارغٌ لغير الراوتر.
  final String wanType;

  final String hostname;
  final String firmware;
  final int? uptimeSeconds;
  final String ssid;
  final String mode;
  final int? signalDbm;
  final int? noiseFloorDbm;
  final int? ccqPercent;
  final int? distanceMeters;
  final int? txRateKbps;
  final int? rxRateKbps;
  final List<LanPort> lanPorts;
  final String? peerMac;
  final int? peerCount;

  /// مجموع عدّادات البايت على واجهات البيانات لحظة القراءة.
  ///
  /// airOS يضعها داخل `interfaces[].status` — نفس الكائن الذي تُقرأ
  /// منه `plugged` و`speed`. كانت تصل في كلّ استجابة وتُرمى.
  ///
  /// ⚠️ عدّاد تراكميّ لا معدّل: المعدّل = فرق قراءتين ÷ الزمن بينهما.
  /// ولا ضمان بوجودها — بعض الإصدارات لا تُصدّرها، فتبقى null.
  final int? rxBytes;
  final int? txBytes;
  final String baseUrl;

  LanPort? get primaryLan => lanPorts.firstWhere(
        (p) => p.plugged,
        orElse: () => lanPorts.isEmpty
            ? const LanPort(name: '', speed: null, plugged: false)
            : lanPorts.first,
      );

  bool get lanUp => primaryLan?.plugged ?? false;
  String? get lanSpeedShort =>
      primaryLan?.plugged == true ? primaryLan?.displaySpeed : null;

  String get signalHealth {
    final s = signalDbm;
    if (s == null) return 'unknown';
    if (s > -65) return 'good';
    if (s > -75) return 'warn';
    return 'bad';
  }

  String get ccqHealth {
    final c = ccqPercent;
    if (c == null) return 'unknown';
    return c >= 80 ? 'good' : 'bad';
  }

  String get lanHealth {
    // الراوتر المنزليّ لا يصدّر حالة منافذه — «مجهول» لا «مفصول» (لا إنذارٌ أحمر كاذب على كلّ راوتر).
    if (isRouter) return 'unknown';
    if (!lanUp) return 'bad';
    // موصولٌ والسرعة مجهولة ليس عطلاً — لا نصبغه بالأحمر.
    if (primaryLan?.speedUnknown ?? false) return 'unknown';
    final s = primaryLan?.speed ?? '';
    final m = RegExp(r'^(\d+)Mbps').firstMatch(s);
    final mbps = m == null ? null : int.tryParse(m.group(1)!);
    if (mbps == null) return 'bad';
    return mbps >= 100 ? 'good' : 'bad';
  }

  int? get snrDb {
    final s = signalDbm;
    final n = noiseFloorDbm;
    if (s == null || n == null) return null;
    return s - n;
  }

  Map<String, dynamic> toJson() => {
        'h': hostname,
        'f': firmware,
        'up': uptimeSeconds,
        'ssid': ssid,
        'm': mode,
        'sig': signalDbm,
        'nf': noiseFloorDbm,
        'ccq': ccqPercent,
        'dist': distanceMeters,
        'tx': txRateKbps,
        'rx': rxRateKbps,
        'lan': lanPorts.map((p) => p.toJson()).toList(),
        'pm': peerMac,
        'pc': peerCount,
        'b': baseUrl,
        if (vendor != 'ubnt') 'vd': vendor,
        if (model.isNotEmpty) 'md': model,
        if (wanOnlineSeconds != null) 'wos': wanOnlineSeconds,
        if (dhcpCount != null) 'dh': dhcpCount,
        if (wanType.isNotEmpty) 'wt': wanType,
      };

  static UbiquitiStatus fromJson(Map<String, dynamic> j) => UbiquitiStatus(
        hostname: (j['h'] ?? '').toString(),
        firmware: (j['f'] ?? '').toString(),
        uptimeSeconds: j['up'] is int ? j['up'] as int : null,
        ssid: (j['ssid'] ?? '').toString(),
        mode: (j['m'] ?? '').toString(),
        signalDbm: j['sig'] is int ? j['sig'] as int : null,
        noiseFloorDbm: j['nf'] is int ? j['nf'] as int : null,
        ccqPercent: j['ccq'] is int ? j['ccq'] as int : null,
        distanceMeters: j['dist'] is int ? j['dist'] as int : null,
        txRateKbps: j['tx'] is int ? j['tx'] as int : null,
        rxRateKbps: j['rx'] is int ? j['rx'] as int : null,
        lanPorts: (j['lan'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => LanPort.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        peerMac: j['pm']?.toString(),
        peerCount: j['pc'] is int ? j['pc'] as int : null,
        baseUrl: (j['b'] ?? '').toString(),
        // مخزَّنٌ قبل حقل المورّد ⇒ يوبيكويتي كما كان.
        vendor: (j['vd'] ?? 'ubnt').toString(),
        model: (j['md'] ?? '').toString(),
        wanOnlineSeconds: j['wos'] is int ? j['wos'] as int : null,
        dhcpCount: j['dh'] is int ? j['dh'] as int : null,
        wanType: (j['wt'] ?? '').toString(),
      );

  /// نسخةٌ بقراءاتٍ حيّة أحدث (نبضة الكرت) — ما لم يُعطَ يبقى كما هو؛ والمنافذ تُستبدل كلّها حين تُعطى.
  UbiquitiStatus withLive({
    int? signalDbm,
    int? noiseFloorDbm,
    int? ccqPercent,
    int? txRateKbps,
    int? rxRateKbps,
    int? uptimeSeconds,
    List<LanPort>? lanPorts,
    int? peerCount,
    int? wanOnlineSeconds,
    int? dhcpCount,
  }) =>
      UbiquitiStatus(
        hostname: hostname,
        firmware: firmware,
        uptimeSeconds: uptimeSeconds ?? this.uptimeSeconds,
        ssid: ssid,
        mode: mode,
        signalDbm: signalDbm ?? this.signalDbm,
        noiseFloorDbm: noiseFloorDbm ?? this.noiseFloorDbm,
        ccqPercent: ccqPercent ?? this.ccqPercent,
        distanceMeters: distanceMeters,
        txRateKbps: txRateKbps ?? this.txRateKbps,
        rxRateKbps: rxRateKbps ?? this.rxRateKbps,
        rxBytes: rxBytes,
        txBytes: txBytes,
        lanPorts: lanPorts ?? this.lanPorts,
        peerMac: peerMac,
        peerCount: peerCount ?? this.peerCount,
        baseUrl: baseUrl,
        vendor: vendor,
        model: model,
        wanOnlineSeconds: wanOnlineSeconds ?? this.wanOnlineSeconds,
        dhcpCount: dhcpCount ?? this.dhcpCount,
        wanType: wanType,
      );
}

class UbiquitiLoginResult {
  const UbiquitiLoginResult({
    required this.baseUrl,
    required this.sessionCookie,
    required this.airosVariant,
    this.csrfToken,
  });
  final String baseUrl;
  final String sessionCookie;
  final String? csrfToken;
  final String airosVariant;
}

/// Final unified snapshot the subscriber detail card renders. One of
/// `ont` / `ubnt` is non-null depending on which probe won.
class DeviceHealthSnapshot {
  const DeviceHealthSnapshot({
    required this.kind,
    required this.ip,
    this.ont,
    this.ubnt,
  });
  final DeviceKind kind;
  final String ip;
  final OntOpticalInfo? ont;
  final UbiquitiStatus? ubnt;

  Map<String, dynamic> toJson() => {
        'k': deviceKindToString(kind),
        'ip': ip,
        if (ont != null) 'ont': ont!.toJson(),
        if (ubnt != null) 'ubnt': ubnt!.toJson(),
      };

  static DeviceHealthSnapshot? fromJson(Map<String, dynamic> j) {
    final k = deviceKindFromString(j['k']?.toString());
    if (k == null) return null;
    final ip = (j['ip'] ?? '').toString();
    if (ip.isEmpty) return null;
    OntOpticalInfo? ont;
    UbiquitiStatus? ubnt;
    if (j['ont'] is Map) {
      ont = OntOpticalInfo.fromJson(Map<String, dynamic>.from(j['ont']));
    }
    if (j['ubnt'] is Map) {
      ubnt = UbiquitiStatus.fromJson(Map<String, dynamic>.from(j['ubnt']));
    }
    return DeviceHealthSnapshot(kind: k, ip: ip, ont: ont, ubnt: ubnt);
  }
}
