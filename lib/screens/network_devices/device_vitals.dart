import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/mikrotik_api.dart';
import '../../api/mimosa_api.dart';
import '../../api/network_devices_api.dart';
import '../../api/ubnt_api.dart';
import '../../models/network_device.dart';
import '../../services/device_stats_cache.dart';
import '../../theme/colors.dart';
import 'widgets/_grade.dart';

/// مقياس واحد في خانة من خانات البطاقة الثلاث.
@immutable
class Vital {
  const Vital({
    required this.label,
    required this.value,
    required this.tone,
    required this.icon,
    this.unit,
  });

  final String label;
  final String value;

  /// أيقونة صغيرة بدل التسمية النصّيّة.
  ///
  /// «المعالج» و«الذاكرة» و«الحرارة» فوق كلّ رقمٍ تستهلك سطراً كاملاً
  /// في كلّ بطاقة، وهي تسمياتٌ تُحفَظ بعد مرّتين. الأيقونة تُعرَّف مرّةً
  /// وتُقرأ دائماً، وتُعيد ذلك السطر إلى الكثافة.
  final IconData icon;

  /// الوحدة منفصلة عن الرقم لتُرسَم بلون مميّز بجانبه — طلب المستخدم
  /// في رسوم الاستهلاك، ونفس المبدأ هنا.
  final String? unit;
  final AppTone tone;

  static const empty = Vital(
      label: '—',
      value: '—',
      tone: AppTone.neutral,
      icon: LucideIcons.minus);
}

/// حالة مقاييس جهاز واحد.
@immutable
class VitalsState {
  const VitalsState({
    this.vitals,
    this.detail,
    this.loading = false,
    this.error,
    this.at,
  });

  final List<Vital>? vitals;

  /// تفصيل المطويّ المفتوح — من نفس الحمولة، فالفتح لا يكلّف شبكة.
  final DeviceDetail? detail;
  final bool loading;
  final String? error;
  final DateTime? at;

  static const idle = VitalsState();

  bool get isFresh =>
      at != null && DateTime.now().difference(at!) < DeviceVitals.freshFor;
}

/// منفذ ومروره — المعدّل محسوب من فارق العدّادات بين جلستين.
@immutable
class PortTraffic {
  const PortTraffic({
    required this.name,
    required this.up,
    this.rxBps,
    this.txBps,
    this.linkSpeed,
  });

  final String name;
  final bool up;

  /// `null` = لا عيّنة سابقة بعد، أو العدّاد ارتدّ (إقلاع الجهاز).
  final int? rxBps;
  final int? txBps;
  final String? linkSpeed;

  int get total => (rxBps ?? 0) + (txBps ?? 0);
}

/// طرفٌ متّصل — عميل لاسلكيّ أو محطّة.
@immutable
class PeerLink {
  const PeerLink({
    required this.name,
    this.signal,
    this.ccq,
    this.txRate,
    this.rxRate,
    this.uptimeSec,
  });

  final String name;
  final int? signal;

  /// جودة الاتّصال ٪ — CCQ.
  ///
  /// الإشارة وحدها تكذب: وصلةٌ بـ−٥٥dBm وسط تداخلٍ شديد تبدو ممتازةً
  /// وهي تُعيد الإرسال باستمرار. وCCQ هو ما يكشف ذلك.
  ///
  /// الصفر يعني «غير متوفّر» لا «جودة صفر» — بعض الطُرُز (airFiber
  /// ٦٠GHz خاصّةً) لا تُرجعه أصلاً.
  final int? ccq;
  final int? txRate;
  final int? rxRate;
  final int? uptimeSec;

  bool get hasCcq => ccq != null && ccq! > 0;
}

/// تفصيل الجهاز — من **نفس حمولة الجلسة** التي ملأت الخانات الثلاث.
///
/// فتح البطاقة لا يكلّف شبكةً: الحمولة تصل كاملةً أصلاً، وكنّا نقرأ
/// منها ثلاثة أرقام ونرمي الباقي.
@immutable
class DeviceDetail {
  const DeviceDetail({
    this.uptime,
    this.firmware,
    this.model,
    this.ports = const [],
    this.peers = const [],
    this.peersLabel = 'المتّصلون',
    this.link = const [],
    this.extras = const [],
  });

  final String? uptime;
  final String? firmware;
  final String? model;
  final List<PortTraffic> ports;
  final List<PeerLink> peers;
  final String peersLabel;

  /// مقاييس الوصلة اللاسلكيّة — قسمٌ خاصّ لا يُدفَن في «النظام».
  ///
  /// CCQ تحديداً: الإشارة وحدها تكذب، ووصلةٌ قويّة وسط تداخلٍ شديد
  /// تبدو ممتازةً وهي تُعيد الإرسال باستمرار. فوضعُها بين MAC والموقع
  /// يُخفي أهمّ رقمٍ تشخيصيّ في الصفحة.
  final List<({String k, String v})> link;

  final List<({String k, String v})> extras;
}

/// حصيلة جلسة واحدة.
@immutable
class ProbeResult {
  const ProbeResult({
    required this.vitals,
    required this.detail,
    required this.counters,
    this.raw,
  });

  final List<Vital> vitals;
  final DeviceDetail detail;

  /// حمولة العلامة كما جاءت — تُحفظ في [DeviceStatsCache] لتُبذَر بها
  /// اللوحة المفردة، فلا يدفع المستخدم ثمن الجلسة مرّتين.
  final Object? raw;

  /// عدّادات البايت الخام — تُحفظ لتُطرح منها عيّنةُ الجلسة القادمة.
  final Map<String, ({int rx, int tx})> counters;
}

/// عيّنة عدّادات سابقة مع لحظتها.
@immutable
class CounterSample {
  const CounterSample(this.counters, this.at);
  final Map<String, ({int rx, int tx})> counters;
  final DateTime at;
}

/// خريطة «العلامة ← ثلاثة مقاييس».
///
/// ── المشكلة ───────────────────────────────────────────────────────
/// العلامات لا تشترك في مقاييسها: UBNT يعطي إشارةً وحرارة، وميكروتك
/// يعطي ذاكرةً ومعالجاً، وميموزا يعطي قدرةً بصريّة ومعدّلاً. جدولٌ
/// موحّد مستحيل.
///
/// ── الحلّ ─────────────────────────────────────────────────────────
/// نُثبّت **المواضع** ونُغيّر **المعاني**: ثلاث خانات في كلّ بطاقة تحمل
/// أهمّ ثلاثة مقاييس لتلك العلامة. فتصطفّ البطاقات بصريّاً وإن اختلفت
/// التسميات، ويقرأ المدير عموداً واحداً بدل أن يُعيد ضبط عينه مع كلّ
/// بطاقة.
///
/// والألوان كلّها من [Grade] — السلّم الموحّد الذي وحّد ٢٤ دالّة تدريج
/// متفرّقة عبر اللوحات الخمس. لا سلّم سادس هنا.
class DeviceVitals {
  DeviceVitals._();

  /// كم تبقى القيمة صالحةً قبل إعادة الجلب.
  ///
  /// أطول من نبضة اللوحة المفردة (٨–١٥ث) عمداً: الجدار يعرض ستّ بطاقات
  /// لا واحدة، والتمرير ذهاباً وإياباً يُعيد بناءها. بلا نافذة صلاحيّة
  /// يصير كلّ تمرير موجة جلسات جديدة.
  static const freshFor = Duration(seconds: 20);

  /// هل تصلح هذه العلامة لجلسة عميقة أصلاً؟
  static bool supports(String brand) =>
      const {'mikrotik', 'ubnt', 'mimosa'}.contains(brand.toLowerCase());

  /// سبب امتناعنا عن الجلب — أو `null` إن كان الجهاز صالحاً.
  ///
  /// نمتنع صراحةً بدل أن نحاول ونفشل: كلّ محاولة فاشلة تحجز خانةً من
  /// ستّ وتنتظر مهلتها كاملةً.
  static String? skipReason(NetworkDevice d) {
    // «غير متّصل» لا «معطّل»: الثانية تعني مُوقَفاً بقرار المدير،
    // وهذا جهازٌ لا يردّ فحسب. وبقيّة التطبيق تستعمل الأولى.
    if (d.lastStatus == 'offline') return 'غير متّصل';
    if (!d.hasCredentials) return 'بلا بيانات دخول';
    if (!supports(d.brand)) return 'لا مقاييس لهذه العلامة';
    return null;
  }

  /// يفتح جلسةً ويُعيد المقاييس والتفصيل معاً. يرمي عند الفشل.
  ///
  /// [prev] عيّنة العدّادات السابقة — بلا سابقةٍ لا يمكن حساب معدّل
  /// مرور، فتُعرض شرطة حتّى الجلسة الثانية.
  static Future<ProbeResult> fetch(NetworkDevice d,
      {CounterSample? prev}) async {
    final creds = await NetworkDevicesApi.getCredentials(d.id);
    switch (d.brand.toLowerCase()) {
      case 'mikrotik':
        return _mikrotik(d, creds, prev);
      case 'ubnt':
        return _ubnt(d, creds, prev);
      case 'mimosa':
        return _mimosa(d, creds);
      default:
        throw StateError('علامة غير مدعومة: ${d.brand}');
    }
  }

  // ── حساب المعدّل من فارق العدّادات ───────────────────────────────

  /// يحوّل عدّادات البايت إلى معدّل بت/ثانية.
  ///
  /// ⚠️ الزمن المستعمل هو الفاصل بين **عيّنتين كاملتين**. أخطر فخّ في
  /// هذا الحساب أن يُؤخذ زمنٌ أقصر من الحقيقيّ: الجدار يجلب كلّ ١٥
  /// ثانية، ولو قسمنا على نصف ثانية لظهر منفذٌ يحمل ١٣٠ ميغا وكأنّه
  /// يحمل أربعة غيغا. (وقع هذا فعلاً في اللوحات المفردة ٢٠٢٦-٠٨-١٣.)
  static ({int? rx, int? tx}) _rate(
    String port,
    int rxNow,
    int txNow,
    CounterSample? prev,
  ) {
    if (prev == null) return (rx: null, tx: null);
    final before = prev.counters[port];
    if (before == null) return (rx: null, tx: null);

    final secs = DateTime.now().difference(prev.at).inMilliseconds / 1000.0;
    // نافذة معقولة: أقلّ من ثانية يُضخّم أيّ ضجيج، وأكثر من خمس دقائق
    // يُعطي متوسّطاً لا معدّلاً حاليّاً.
    if (secs < 1 || secs > 300) return (rx: null, tx: null);

    // ارتداد العدّاد = إقلاع الجهاز أو التفاف ٣٢-بت. لا نطرح فنُخرج
    // رقماً سالباً أو ضخماً كاذباً.
    if (rxNow < before.rx || txNow < before.tx) return (rx: null, tx: null);

    return (
      rx: ((rxNow - before.rx) * 8 / secs).round(),
      tx: ((txNow - before.tx) * 8 / secs).round(),
    );
  }

  /// «١٢ يوماً» من ثوانٍ.
  static String fmtUptime(int seconds) {
    if (seconds <= 0) return '—';
    final d = Duration(seconds: seconds);
    if (d.inDays >= 1) return '${d.inDays} يوماً';
    if (d.inHours >= 1) return '${d.inHours} ساعة';
    return '${d.inMinutes} دقيقة';
  }

  /// «٣٤٠ M» من بت/ثانية — للمرور.
  static String fmtBps(int? bps) {
    if (bps == null) return '—';
    if (bps < 1000) return '$bps';
    if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(0)} K';
    if (bps < 1000000000) return '${(bps / 1000000).toStringAsFixed(1)} M';
    return '${(bps / 1000000000).toStringAsFixed(2)} G';
  }

  // ── ميكروتك: معالج · ذاكرة · حرارة ───────────────────────────────

  static Future<ProbeResult> _mikrotik(
      NetworkDevice d, Map<String, dynamic> creds, CounterSample? prev) async {
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (user.isEmpty || pass.isEmpty) throw StateError('بيانات دخول ناقصة');

    final s = await MikrotikApi.fetchStats(
      ip: d.ip,
      port: d.apiPort ?? 8728,
      user: user,
      pass: pass,
    );

    final counters = <String, ({int rx, int tx})>{};
    final ports = <PortTraffic>[];
    for (final i in s.interfaces) {
      if (i.disabled) continue;
      final rx = i.rxBytes ?? 0;
      final tx = i.txBytes ?? 0;
      counters[i.name] = (rx: rx, tx: tx);
      final r = _rate(i.name, rx, tx, prev);
      ports.add(PortTraffic(
        name: i.name,
        up: i.running,
        rxBps: r.rx,
        txBps: r.tx,
        linkSpeed: i.linkSpeed,
      ));
    }

    final peers = [
      for (final c in s.wirelessClients)
        PeerLink(
          name: c.hostname?.isNotEmpty == true
              ? c.hostname!
              : (c.ip?.isNotEmpty == true ? c.ip! : c.mac),
          signal: c.signalStrength,
          // نُفضّل txCcq: يقيس جودة ما نُرسله إلى العميل، وهو ما يشعر
          // به المشترك. ونسقط إلى rxCcq حين لا يُرجع الطرازُ الأوّل.
          ccq: c.txCcq > 0 ? c.txCcq : (c.rxCcq > 0 ? c.rxCcq : null),
          txRate: c.txRate,
          rxRate: c.rxRate,
          uptimeSec: c.uptime,
        ),
    ];

    return ProbeResult(
      vitals: [
        Vital(
          label: 'المعالج',
          value: '${s.cpuLoad}',
          unit: '٪',
          icon: LucideIcons.cpu,
          tone: Grade.percentLowerBetter(s.cpuLoad),
        ),
        Vital(
          label: 'الذاكرة',
          value: '${s.memUsedPercent}',
          unit: '٪',
          icon: LucideIcons.memoryStick,
          tone: Grade.percentLowerBetter(s.memUsedPercent),
        ),
        // الحرارة غير متوفّرة على كلّ الطُرُز (CCR2116 بلا مجسّ مثلاً).
        // نُظهر شرطةً لا صفراً — الصفر رقمٌ يكذب.
        s.temperature == null
            ? Vital.empty.withIcon(LucideIcons.thermometer)
            : Vital(
                label: 'الحرارة',
                value: '${s.temperature}',
                unit: '°',
                icon: LucideIcons.thermometer,
                tone: Grade.temperature(s.temperature),
              ),
      ],
      detail: DeviceDetail(
        uptime: s.uptime.isNotEmpty ? s.uptime : null,
        firmware: s.version.isNotEmpty ? s.version : null,
        model: s.boardName.isNotEmpty ? s.boardName : null,
        ports: ports,
        peers: peers,
        peersLabel: 'العملاء اللاسلكيّون',
        extras: [
          if (s.pppActiveCount > 0)
            (k: 'جلسات PPP', v: '${s.pppActiveCount}'),
          if (s.voltage != null)
            (k: 'الفولتيّة', v: '${s.voltage!.toStringAsFixed(1)} V'),
          if (s.fans.isNotEmpty) (k: 'المراوح', v: '${s.fans.length}'),
        ],
      ),
      counters: counters,
      raw: s,
    );
  }

  // ── UBNT: الإشارة · المعالج · الحرارة ────────────────────────────

  static Future<ProbeResult> _ubnt(
      NetworkDevice d, Map<String, dynamic> creds, CounterSample? prev) async {
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (user.isEmpty || pass.isEmpty) throw StateError('بيانات دخول ناقصة');

    final s = await UbntApi.fetchStats(
      ip: d.ip,
      port: d.apiPort ?? 22,
      user: user,
      pass: pass,
    );
    final w = s.wireless;

    final counters = <String, ({int rx, int tx})>{};
    final ports = <PortTraffic>[];
    for (final i in s.interfaces) {
      if (!i.enabled) continue;
      final rx = i.rxBytes ?? 0;
      final tx = i.txBytes ?? 0;
      counters[i.ifname] = (rx: rx, tx: tx);
      final r = _rate(i.ifname, rx, tx, prev);
      ports.add(PortTraffic(
        name: i.ifname,
        up: i.plugged,
        rxBps: r.rx,
        txBps: r.tx,
        linkSpeed: i.speed != null && i.speed! > 0 ? '${i.speed}M' : null,
      ));
    }

    final peers = [
      for (final st in s.stations)
        PeerLink(
          name: st.hostname?.isNotEmpty == true
              ? st.hostname!
              : (st.ip?.isNotEmpty == true ? st.ip! : st.mac),
          signal: st.signal,
          ccq: st.ccq > 0 ? st.ccq : null,
          txRate: st.txRate,
          rxRate: st.rxRate,
          uptimeSec: st.linkUptimeSec ?? st.connTime,
        ),
    ];

    return ProbeResult(
      vitals: [
        // نقطة الوصول لا إشارة لها (هي المصدر) — والصفر هنا يعني «غير
        // متوفّر» لا «إشارة صفر dBm»، وهي قيمة ممتازة لو صُدّقت.
        (w == null || w.signal == 0)
            ? Vital.empty.withIcon(LucideIcons.signal)
            : Vital(
                label: 'الإشارة',
                value: '${w.signal}',
                unit: 'dBm',
                icon: LucideIcons.signal,
                tone: Grade.signal(w.signal),
              ),
        Vital(
          label: 'المعالج',
          value: '${s.host.cpuload}',
          unit: '٪',
          icon: LucideIcons.cpu,
          tone: Grade.percentLowerBetter(s.host.cpuload),
        ),
        s.host.temperature == 0
            ? Vital.empty.withIcon(LucideIcons.thermometer)
            : Vital(
                label: 'الحرارة',
                value: '${s.host.temperature}',
                unit: '°',
                icon: LucideIcons.thermometer,
                tone: Grade.temperature(s.host.temperature),
              ),
      ],
      detail: DeviceDetail(
        uptime: fmtUptime(s.host.uptime),
        firmware: s.host.fwversion.isNotEmpty ? s.host.fwversion : null,
        model: s.host.devmodel.isNotEmpty ? s.host.devmodel : null,
        ports: ports,
        peers: peers,
        peersLabel: 'المحطّات',
        link: [
          if (w != null && w.ccq > 0) (k: 'الجودة CCQ', v: '${w.ccq}٪'),
          if (w != null && w.hasNoise)
            (k: 'أرضيّة الضجيج', v: '${w.noise} dBm'),
          if (w != null && w.explicitSnr > 0)
            (k: 'SNR', v: '${w.explicitSnr} dB'),
          if (w != null && (w.txRate > 0 || w.rxRate > 0))
            (k: 'المعدّل', v: '${w.rxRate}/${w.txRate} Mbps'),
          if (w != null && w.frequency > 0)
            (k: 'التردّد', v: '${w.frequency} MHz'),
          if (w != null && w.distance > 0) (k: 'المسافة', v: '${w.distance} م'),
        ],
        extras: [
          if (w != null && w.essid.isNotEmpty) (k: 'الشبكة', v: w.essid),
          if (w != null && w.mode.isNotEmpty) (k: 'الوضع', v: w.mode),
          if (s.lanSpeed != null) (k: 'منفذ LAN', v: s.lanSpeed!),
        ],
      ),
      counters: counters,
      raw: s,
    );
  }

  // ── ميموزا: قدرة الاستقبال · معدّل الاستقبال · الحرارة ───────────
  //
  // ⚠️ بلا منافذ: SNMP هنا يُرجع مقاييس الوصلة لا عدّادات المنافذ،
  // فلا فارق عدّادات يُحسب. المرور يظهر معدّلاً لحظيّاً في «إضافات».

  static Future<ProbeResult> _mimosa(
      NetworkDevice d, Map<String, dynamic> creds) async {
    final community =
        (creds['community'] ?? creds['user'] ?? 'public').toString();
    final s = await MimosaApi.fetchStats(
      host: d.ip,
      port: d.apiPort ?? 161,
      community: community,
    );
    return ProbeResult(
      vitals: [
        s.totalRxPowerDbm == null
            ? Vital.empty.withIcon(LucideIcons.signal)
            : Vital(
                label: 'الاستقبال',
                value: s.totalRxPowerDbm!.toStringAsFixed(0),
                unit: 'dBm',
                icon: LucideIcons.signal,
                tone: Grade.rxPower(s.totalRxPowerDbm),
              ),
        s.phyRxRateMbps == null
            ? Vital.empty.withIcon(LucideIcons.gauge)
            : Vital(
                label: 'معدّل RX',
                value: '${s.phyRxRateMbps}',
                unit: 'M',
                icon: LucideIcons.gauge,
                tone: Grade.speedMbps(s.phyRxRateMbps),
              ),
        s.temperatureC == null
            ? Vital.empty.withIcon(LucideIcons.thermometer)
            : Vital(
                label: 'الحرارة',
                value: s.temperatureC!.toStringAsFixed(0),
                unit: '°',
                icon: LucideIcons.thermometer,
                tone: Grade.temperature(s.temperatureC),
              ),
      ],
      detail: DeviceDetail(
        // مدّة الوصلة وحدها — لا سقوطَ إلى عمر وكيل SNMP.
        //
        // الأوّل ما يهمّ من يراقب برجاً، والثاني يُصفَّر بإعادة تشغيل
        // وكيلٍ فيقول إنّ البرج سقط قبل دقائق وهو لم يتزحزح. شرطةٌ
        // أصدق من رقمٍ يكذب.
        uptime: s.linkUptimeSec == null ? null : fmtUptime(s.linkUptimeSec!),
        firmware: s.firmwareVersion,
        model: s.deviceName,
        peersLabel: 'المحطّات',
        link: [
          if (s.ssid?.isNotEmpty ?? false) (k: 'الوصلة', v: s.ssid!),
          if (s.channelWidthMhz != null)
            (k: 'عرض القناة', v: '${s.channelWidthMhz} MHz'),
          if (s.phyTxRateMbps != null)
            (k: 'معدّل TX', v: '${s.phyTxRateMbps} Mbps'),
          if (s.totalTxPowerDbm != null)
            (k: 'قدرة الإرسال',
                v: '${s.totalTxPowerDbm!.toStringAsFixed(0)} dBm'),
          if (s.perRxRatePct != null)
            (k: 'أخطاء RX', v: '${s.perRxRatePct!.toStringAsFixed(1)}٪'),
          if (s.perTxRatePct != null)
            (k: 'أخطاء TX', v: '${s.perTxRatePct!.toStringAsFixed(1)}٪'),
        ],
        extras: [
          if (s.serialNumber != null) (k: 'التسلسل', v: s.serialNumber!),
        ],
      ),
      counters: const {},
      raw: s,
    );
  }
}

extension on Vital {
  Vital withIcon(IconData i) =>
      Vital(label: label, value: value, tone: tone, icon: i);
}

/// مخزن المقاييس — مُنبّه لكلّ جهاز على حدة.
///
/// ⚠️ مُنبّهٌ لكلّ بطاقة، لا `setState` على الشاشة كلّها: الجدار قد يحمل
/// ثمانين بطاقة، وإعادة بنائها جميعاً كلّما وصلت قيمةُ واحدةٍ تُسقط
/// إطارات التمرير — وهو ما يُفترض بهذه الميزة أن تتجنّبه أصلاً.
class VitalsStore {
  final Map<int, ValueNotifier<VitalsState>> _byId = {};

  ValueNotifier<VitalsState> of(int deviceId) =>
      _byId.putIfAbsent(deviceId, () => ValueNotifier(VitalsState.idle));

  void set(int deviceId, VitalsState s) => of(deviceId).value = s;

  /// ⚠️ العيّنات في [DeviceStatsCache] لا هنا.
  ///
  /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «بكلّ جهاز أنقر عليه لازم يعيد إرسال الطلب».
  /// كانت تعيش في هذا المخزن، والمخزن في حالة الشاشة — فالخروج من
  /// «نظرة عامّة» يمحوها، والعودة تبدأ من «يقيس…».
  CounterSample? sampleOf(int deviceId) {
    final s = DeviceStatsCache.instance.sampleOf(deviceId);
    return s == null ? null : CounterSample(s.counters, s.at);
  }

  void saveSample(int deviceId, Map<String, ({int rx, int tx})> counters) =>
      DeviceStatsCache.instance.putSample(deviceId, counters);

  /// ⚠️ نتخلّص من المُنبّهات وحدها. القيم نفسها في المخزن العالميّ
  /// وتبقى — وهي كلّ الفائدة.
  void dispose() {
    for (final n in _byId.values) {
      n.dispose();
    }
    _byId.clear();
  }
}
