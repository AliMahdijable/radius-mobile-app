import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/agent_net_presence.dart';
import '../../services/vitals_reporter.dart';
import '../../services/vpn_now.dart';
import '../../api/bdcom_epon.dart';
import '../../api/cisco_api.dart';
import '../../api/hsgq_olt.dart';
import '../../api/mikrotik_api.dart';
import '../../api/mimosa_api.dart';
import '../../api/network_devices_api.dart';
import '../../api/olt_fiber_reads.dart';
import '../../api/olt_profile.dart';
import '../../api/ruijie_api.dart';
import '../../api/snmp_client.dart';
import '../../api/ubnt_api.dart';
import '../../api/vsol_olt_api.dart';
import '../../models/network_device.dart';
import '../../services/device_stats_cache.dart';
import '../../services/fiber/fiber_monitor.dart';
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
    this.physical = true,
    this.halfDuplex = false,
    this.linkDowns,
    this.errors,
    this.sfpRx,
    this.poeStatus,
  });

  final String name;
  final bool up;

  /// «الفحص الشامل» للسويجات (٦ نوفمبر): half-duplex صريح، انقطاعات الربط والأخطاء منذ الإقلاع، ضوء الـSFP (dBm)، وحال الـPoE —
  /// ما يقرؤه الطراز وحده (مايكروتك محلّيّاً، وعبر الـVPN من `pl`)؛ الغائب null.
  final bool halfDuplex;
  final int? linkDowns;
  final int? errors;
  final double? sfpRx;
  final String? poeStatus;

  /// منفذ إيثرنت فعليّ (ether/sfp/combo…) لا واجهةٌ منطقيّة (جلسة PPP، نفق، جسر، VLAN، لاسلكيّ). المالك ٣١ أكتوبر: «سيرفر
  /// التوزيع شو عارض ١٤٨؟ ذوله ppp مالنا علاقة بيهن — السويجات والسيرفرات كلنا بس الإيثرات ومعدّلات السحب».
  final bool physical;

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
    this.txSignal,
    this.mac,
    this.ccq,
    this.txRate,
    this.rxRate,
    this.uptimeSec,
  });

  final String name;

  /// ما نستقبله نحن من الطرف (rx عند السكتر).
  final int? signal;

  /// إشارة الطرف من جهتنا — كيف يستقبلنا (مايكروتك tx-signal-strength، يوبيكويتي remote/tx signal)؛ null = لا يعطيها الطراز.
  /// المالك ٦ نوفمبر: «مفروض تقره الاشارة من عدنا وليس rx او تظهرهن الاثنين».
  final int? txSignal;

  /// ماك الطرف — للمطابقة بماك جلسة المشترك ونسخه (المالك ٦ نوفمبر: «لازم تفعل امكانيه نسخ الماك… او النقر عليه يفتحله اليوزر»).
  final String? mac;

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
    this.glance = const DeviceGlance(),
    this.onuLights = const [],
  });

  /// أولت: ضوء كلّ ONU متّصلة مقروء (الأضعف أوّلاً) — «الفحص الشامل» وحده يطلبه (detailed).
  final List<OnuLight> onuLights;

  final String? uptime;
  final String? firmware;
  final String? model;
  final List<PortTraffic> ports;
  final List<PeerLink> peers;
  final String peersLabel;

  /// أرقام البطاقة الكبيرة (٣١ أكتوبر) — من الحمولة نفسها، أرقامٌ لا نصوص.
  final DeviceGlance glance;

  /// مقاييس الوصلة اللاسلكيّة — قسمٌ خاصّ لا يُدفَن في «النظام».
  ///
  /// CCQ تحديداً: الإشارة وحدها تكذب، ووصلةٌ قويّة وسط تداخلٍ شديد
  /// تبدو ممتازةً وهي تُعيد الإرسال باستمرار. فوضعُها بين MAC والموقع
  /// يُخفي أهمّ رقمٍ تشخيصيّ في الصفحة.
  final List<({String k, String v})> link;

  final List<({String k, String v})> extras;
}

/// نظرة «البطاقات الكبيرة» على الجهاز (المالك ٣١ أكتوبر: «كارتات كبار بيها المعلومات المهمّة… للسكتر المعلومات الحسّاسة وعدد
/// المتصلين وتفاصيلهن بشكل مختصر، السويجات، اللنكات، الأولتي… بدقّة»).
///
/// ⚠️ أرقامٌ من **حمولة الجلسة نفسها** التي ملأت الخانات الثلاث — لا جلسة إضافيّة. و`null` = لا يقرؤه هذا الجهاز أو طرازه،
/// فيُعرض «—» لا صفراً: الصفر رقمٌ يكذب (إشارة 0 dBm ممتازةٌ لو صُدّقت، وCCQ صفرٌ يعني عند بعض الطُرُز «غير متوفّر»).
/// العملاء والمنافذ في [DeviceDetail.peers]/[DeviceDetail.ports] كما هي.
@immutable
class DeviceGlance {
  const DeviceGlance({
    this.cpu,
    this.mem,
    this.temp,
    this.voltage,
    this.poeWatts,
    this.ppp,
    this.signal,
    this.noise,
    this.snr,
    this.ccq,
    this.freqMhz,
    this.widthMhz,
    this.distanceM,
    this.rxRateMbps,
    this.txRateMbps,
    this.ssid,
    this.mode,
    this.signalPct,
    this.isAp,
    this.onusOnline,
    this.onusTotal,
    this.pons = const [],
    this.uplinksUp,
    this.uplinksTotal,
    this.uptimeSec,
    this.linkUptime = false,
    this.peersKnown = false,
  });

  /// مدّة التشغيل بالثواني — أو مدّة **الوصلة** حين [linkUptime] (ميموزا: عمر وكيل SNMP يُصفَّر بلا سقوط، فلا يُعرض).
  final int? uptimeSec;
  final bool linkUptime;

  /// قائمة العملاء/المحطّات في [DeviceDetail.peers] قُرئت فعلاً — فراغها «لا متّصلين» لا «لم تُقرأ بعد». القراءة الخفيفة
  /// (ميكروتك بلا جدول التسجيل، ميموزا بلا محطّاتها) تتركها false فلا يظهر «0 متّصل» كاذب.
  final bool peersKnown;

  /// المعالج والذاكرة ٪، الحرارة °م، الفولتيّة، استهلاك PoE (واط)، جلسات PPP.
  final int? cpu, mem, temp;
  final double? voltage, poeWatts;
  final int? ppp;

  /// الوصلة اللاسلكيّة كما يراها **هذا** الجهاز: إشارته (dBm)، الضجيج، SNR، CCQ ٪، التردّد وعرض القناة (MHz)، المسافة (م)،
  /// وسرعة الربط استقبالاً/إرسالاً (Mbps). لنقطة وصولٍ (سكتر) لا إشارة لها — هي المصدر — وإشاراتها عند عملائها.
  final int? signal, noise, snr, ccq, freqMhz, widthMhz, distanceM, rxRateMbps, txRateMbps;
  final String? ssid, mode;

  /// جودة الإشارة ٪ (60GHz ميكروتك — `signal` في monitor نسبةٌ لا dBm، ولا CCQ لها).
  final int? signalPct;

  /// نقطة وصول تخدم عملاء (true)، أو محطّةٌ/طرف وصلة (false)، أو لا لاسلكيّ (null).
  final bool? isAp;

  /// الأولت: المشتركون المتّصلون/الكلّ، منافذ PON، ومنافذ الربط (المتّصلة/الكلّ).
  final int? onusOnline, onusTotal;
  final List<PonGlance> pons;
  final int? uplinksUp, uplinksTotal;
}

/// منفذ PON في البطاقة الكبيرة: اسمه وحالته ومشتركوه المتّصلون من الكلّ.
@immutable
class PonGlance {
  const PonGlance(this.label, {required this.up, required this.online, required this.total});
  final String label;
  final bool up;
  final int online, total;
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
  ///
  /// ٢٢ أكتوبر (المالك: «بالنظرة العامة الأولتي ما يعرض ملخّص مثل المايكروتك
  /// وUBNT، وكذلك السسكو والروجي»): صارت للأولتيات (VSOL وBDCOM) وسسكو
  /// وروجي خاناتها الثلاث — وحمولتها تبذر لوحتها المفردة فتُفتح بأرقامها
  /// فوراً كميكروتك.
  ///
  /// والأولت لا يُعرَف بعلامته وحدها (سجلّاتٌ قديمة `other`/`vsol`، وسويتش
  /// BDCOM يحمل علامة `bdcom` نفسها) — فيحكمه [OltProfile] في [skipReason].
  static bool supports(String brand) => const {
        'mikrotik',
        'ubnt',
        'mimosa',
        'cisco',
        'ruijie',
      }.contains(brand.toLowerCase());

  /// أولت: بالعلامة، أو سجلٌّ قديمٌ طرازه يقول VSOL/BDCOM (‏`OltProfile`).
  static bool _isOlt(NetworkDevice d) => OltProfile.fromDevice(d).opensOltPanel;

  /// سبب امتناعنا عن الجلب — أو `null` إن كان الجهاز صالحاً.
  ///
  /// نمتنع صراحةً بدل أن نحاول ونفشل: كلّ محاولة فاشلة تحجز خانةً من
  /// ستّ وتنتظر مهلتها كاملةً.
  /// سبب الامتناع خارج شبكة الوكيل — البطاقة الكبيرة تعرضه سطراً ([DeviceBigCard]).
  static const offNetworkReason = 'خارج شبكتك';

  static String? skipReason(NetworkDevice d) {
    // ٥ نوفمبر: خارج شبكة الوكيل (أو «وضع VPN») لا جلسة تصل الجهاز من الموبايل — محاولاتٌ تفشل وتحجز الخانات، وتُظهر
    // «راجع الإعدادات» لجهازٍ سليم (حاله من الـVPN «متّصل» وقراءته تفشل)
    if (VpnNow.mode.value || AgentNetPresence.isOff) return offNetworkReason;
    // «غير متّصل» لا «معطّل»: الثانية تعني مُوقَفاً بقرار المدير،
    // وهذا جهازٌ لا يردّ فحسب. وبقيّة التطبيق تستعمل الأولى.
    if (d.lastStatus == 'offline') return 'غير متّصل';
    if (!d.hasCredentials) return 'بلا بيانات دخول';
    final olt = _isOlt(d);
    if (!supports(d.brand) && !olt) return 'لا مقاييس لهذه العلامة';
    // كلوحاتها المفردة: الأولت وروجي بـSNMP، وسسكو بـSSH/Telnet.
    if ((olt || d.brand == 'ruijie') && d.protocol != 'snmp') return 'اختر SNMP';
    if (d.brand == 'cisco' && !{'ssh', 'telnet'}.contains(d.protocol)) {
      return 'اختر SSH أو Telnet';
    }
    // ميكروتك: API (ثمّ الويب وSSH تلقائيّاً) أو SSH أو SNMP — Telnet وحده لا يُقرأ.
    if (d.brand == 'mikrotik' && d.protocol == 'telnet') return 'اختر API أو SSH أو SNMP';
    return null;
  }

  /// يفتح جلسةً ويُعيد المقاييس والتفصيل معاً. يرمي عند الفشل.
  ///
  /// [prev] عيّنة العدّادات السابقة — بلا سابقةٍ لا يمكن حساب معدّل
  /// مرور، فتُعرض شرطة حتّى الجلسة الثانية.
  /// [detailed] يجلب التفاصيل (العملاء · المنافذ) — للبطاقة المفتوحة
  /// واللوحة المفردة. والمطويّة تكتفي بالثلاثة.
  ///
  /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «جهاز واحد فقط ظهر معلومات، البقيّة تكتب
  /// يقيس». والبطاقة المطويّة كانت تدفع ثمن الجلسة كاملةً لثلاثة
  /// أرقام: جدول اللاسلكيّ، ثمّ جدول التسجيل، ثمّ صيغةٌ ثانية، ثمّ
  /// جلسة SSH — نحو خمس عشرة ثانية لما يصل في أقلّ من ثانيتين.
  /// وبستّ خانات، كلّ جلسةٍ طويلة تحجب خمس بطاقات.
  /// «المعلومات الحيّة» من فحص الـVPN (٥ نوفمبر — المالك: «المعلومات الحيه مال الاجهزه ماتنعرض عبر vpn هم؟»): الخادم يقرأ الجهاز
  /// عبر النفق (مايكروتك بالـAPI، يوبيكويتي بالويب، الأولت بـSNMP) ⇒ الخانات الثلاث نفسها بمواضعها لكلّ علامة كقراءة الموبايل
  /// ([_mikrotik] · [_ubnt] · [oltProbeResult]). المعدّلات منفذاً منفذاً ليست فيها — تلك من موبايلك حين ترجع لشبكتك.
  static VitalsState fromVpn(Map<String, dynamic> v, {DateTime? at}) {
    int? n(Object? x) => x is num ? x.round() : int.tryParse('${x ?? ''}');
    double? d(Object? x) => x is num ? x.toDouble() : double.tryParse('${x ?? ''}');
    String? s(Object? x) => x == null || '$x'.trim().isEmpty ? null : '$x'.trim();
    List<Map> list(Object? x) => x is List ? x.whereType<Map>().toList() : const [];
    final kind = '${v['kind'] ?? ''}';
    final when = at ?? DateTime.now();
    Vital pct(String label, int? val, IconData icon) => val == null
        ? Vital.empty.withIcon(icon)
        : Vital(label: label, value: '$val', unit: '٪', icon: icon, tone: Grade.percentLowerBetter(val));
    Vital temp(int? t) => t == null
        ? Vital.empty.withIcon(LucideIcons.thermometer)
        : Vital(label: 'الحرارة', value: '$t', unit: '°', icon: LucideIcons.thermometer, tone: Grade.temperature(t));

    if (kind == 'olt') {
      final total = n(v['total']) ?? 0;
      final online = n(v['online']) ?? 0;
      final pons = [
        for (final p in list(v['pons']))
          PonGlance(s(p['label']) ?? '', up: p['up'] == true, online: n(p['online']) ?? 0, total: n(p['total']) ?? 0),
      ];
      final ponUp = pons.where((p) => p.up).length;
      final onPct = total == 0 ? null : online * 100 / total;
      return VitalsState(
        vitals: [
          Vital(
            label: 'المشتركون',
            value: '$online',
            unit: '/$total',
            icon: LucideIcons.users,
            tone: onPct == null ? AppTone.neutral : Grade.percentHigherBetter(onPct),
          ),
          Vital(
            label: 'منافذ PON',
            value: '$ponUp',
            unit: '/${pons.length}',
            icon: LucideIcons.splitSquareVertical,
            tone: pons.isEmpty ? AppTone.neutral : Grade.percentHigherBetter(ponUp * 100 / pons.length),
          ),
          Vital.empty.withIcon(LucideIcons.cpu),
        ],
        detail: DeviceDetail(
          extras: [for (final p in pons) (k: p.label, v: '${p.online}/${p.total}')],
          glance: DeviceGlance(onusOnline: online, onusTotal: total, pons: pons),
          onuLights: [
            for (final o in list(v['onus']))
              if (d(o['rx']) case final rx?) OnuLight(name: s(o['n']) ?? s(o['k']) ?? '—', rx: rx, mac: s(o['m'])),
          ],
        ),
        at: when,
      );
    }

    final up = n(v['up']);
    final ppp = n(v['ppp']);
    final glance = DeviceGlance(
      uptimeSec: up,
      peersKnown: v['peers'] is List,
      cpu: n(v['cpu']),
      mem: n(v['mem']),
      temp: n(v['temp']),
      voltage: d(v['volt']),
      ppp: ppp != null && ppp > 0 ? ppp : null,
      signal: n(v['sig']),
      ccq: n(v['ccq']),
      freqMhz: n(v['freq']),
      widthMhz: n(v['width']),
      distanceM: n(v['dist']),
      rxRateMbps: n(v['rx']),
      txRateMbps: n(v['tx']),
      ssid: s(v['ssid']),
      mode: s(v['mode']),
      isAp: v['ap'] is bool ? v['ap'] as bool : null,
    );
    final ports = <PortTraffic>[];
    final pt = v['ports'];
    final pl = list(v['pl']);
    if (pl.isNotEmpty) {
      // «الفحص الشامل» (٦ نوفمبر): لكلّ منفذٍ فعليّ اسمه وحاله وسرعته والدوبلكس والانقطاعات والأخطاء وضوء الـSFP والـPoE
      for (final p in pl.take(64)) {
        ports.add(PortTraffic(
          name: s(p['n']) ?? '—',
          up: p['r'] == true,
          linkSpeed: s(p['sp']),
          halfDuplex: p['fd'] == false,
          linkDowns: n(p['ld']),
          errors: n(p['er']),
          sfpRx: d(p['sfp']),
          poeStatus: s(p['poe']),
        ));
      }
    } else if (pt is Map) {
      final upN = n(pt['up']) ?? 0;
      final total = n(pt['total']) ?? 0;
      for (var k = 0; k < total && k < 64; k++) {
        ports.add(PortTraffic(name: 'ether${k + 1}', up: k < upN));
      }
    }
    final peers = [
      for (final p in list(v['peers']))
        PeerLink(
          name: s(p['n']) ?? '—',
          signal: n(p['s']),
          txSignal: n(p['ts']),
          mac: s(p['m']),
          ccq: n(p['q']),
          txRate: n(p['tx']),
          rxRate: n(p['rx']),
          uptimeSec: n(p['up']),
        ),
    ];
    final airos = kind == 'airos';
    return VitalsState(
      vitals: airos
          ? [
              glance.signal == null
                  ? Vital.empty.withIcon(LucideIcons.signal)
                  : Vital(
                      label: 'الإشارة',
                      value: '${glance.signal}',
                      unit: 'dBm',
                      icon: LucideIcons.signal,
                      tone: Grade.signal(glance.signal),
                    ),
              pct('المعالج', glance.cpu, LucideIcons.cpu),
              temp(glance.temp),
            ]
          : [
              pct('المعالج', glance.cpu, LucideIcons.cpu),
              pct('الذاكرة', glance.mem, LucideIcons.memoryStick),
              temp(glance.temp),
            ],
      detail: DeviceDetail(
        uptime: up == null ? null : fmtUptime(up),
        firmware: s(v['fw']),
        model: s(v['model']),
        ports: ports,
        peers: peers,
        peersLabel: airos ? 'المحطّات' : 'العملاء اللاسلكيّون',
        extras: [
          if (glance.ppp != null) (k: 'جلسات PPP', v: '${glance.ppp}'),
          if (glance.voltage != null) (k: 'الفولتيّة', v: '${glance.voltage!.toStringAsFixed(1)} V'),
          (k: 'المصدر', v: 'عبر VPN'),
        ],
        glance: glance,
      ),
      at: when,
    );
  }

  static Future<ProbeResult> fetch(NetworkDevice d,
      {CounterSample? prev, bool detailed = false}) async {
    final r = await _fetch(d, prev: prev, detailed: detailed);
    // «القراءات الحسّاسة» (٤ نوفمبر): ما قُرئ يُرفع للخادم — المعالج والحرارة والفولتيّة والإشارة وCCQ ([VitalsReporter]؛ لا شيء ما لم
    // تُفتح للشركة)
    VitalsReporter.instance.record(d, r.detail.glance, peers: r.detail.peers);
    return r;
  }

  static Future<ProbeResult> _fetch(NetworkDevice d, {CounterSample? prev, bool detailed = false}) async {
    final creds = await NetworkDevicesApi.getCredentials(d.id);
    if (_isOlt(d)) return _olt(d, creds, detailed: detailed);
    switch (d.brand.toLowerCase()) {
      case 'mikrotik':
        return _mikrotik(d, creds, prev, detailed);
      case 'ubnt':
        return _ubnt(d, creds, prev);
      case 'mimosa':
        return _mimosa(d, creds, detailed);
      case 'cisco':
        return _cisco(d, creds, detailed);
      case 'ruijie':
        return _ruijie(d, creds, prev);
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

  static Future<ProbeResult> _mikrotik(NetworkDevice d,
      Map<String, dynamic> creds, CounterSample? prev, bool detailed) async {
    final s = await MikrotikApi.fetchStatsFor(
      ip: d.ip,
      protocol: d.protocol,
      apiPort: d.apiPort,
      creds: creds,
      vitalsOnly: !detailed,
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
        // RouterOS يسمّي كلّ منفذٍ فعليّ (إيثر، SFP، كومبو) بالنوع ether؛ وغيره منطقيّ (pppoe-in، أنفاق، جسر، vlan، wlan).
        physical: i.type == 'ether',
        halfDuplex: i.halfDuplex,
        linkDowns: i.linkDowns,
        errors: i.errors,
        sfpRx: i.sfpRxPower,
        poeStatus: i.poeStatus,
      ));
    }

    final peers = [
      for (final c in s.wirelessClients)
        PeerLink(
          // كلوحة المايكروتك: اسم DHCP ثمّ تعليق جدول التسجيل (غالباً يوزر المشترك) ثمّ العنوان ثمّ الـMAC.
          name: c.hostname?.isNotEmpty == true
              ? c.hostname!
              : (c.comment?.isNotEmpty == true
                  ? c.comment!
                  : (c.ip?.isNotEmpty == true ? c.ip! : c.mac)),
          signal: c.signalStrength,
          txSignal: c.txSignalStrength != 0 ? c.txSignalStrength : null,
          mac: c.mac,
          // نُفضّل txCcq: يقيس جودة ما نُرسله إلى العميل، وهو ما يشعر
          // به المشترك. ونسقط إلى rxCcq حين لا يُرجع الطرازُ الأوّل.
          ccq: c.txCcq > 0 ? c.txCcq : (c.rxCcq > 0 ? c.rxCcq : null),
          txRate: c.txRate,
          rxRate: c.rxRate,
          uptimeSec: c.uptime,
        ),
      // 60 GHz: الطرف الآخر من `/interface/w60g/monitor` — لا جدول تسجيلٍ لها. سرعة الربط باتّجاه الإرسال وحده،
      // فلا رقم للاستقبال (لا صفر).
      for (final l in s.w60gLinks)
        if (l.connected) PeerLink(name: l.remoteMac ?? l.iface, signal: l.rssi, txRate: l.phyRateMbps),
    ];

    // ── البطاقة الكبيرة: الوصلة كما يراها هذا الجهاز ─────────────
    // اللاسلكيّ الشغّال الأوّل يعطي التردّد والعرض والوضع. نقطة الوصول (ap-bridge/bridge/wds-master) لا إشارة لها — إشاراتها
    // عند عملائها؛ والمحطّة إشارتها وجودتها في جدول تسجيلها (الطرف الآخر وحده). و60GHz من monitor.
    MikrotikWireless? wl;
    for (final w in s.wirelessInterfaces) {
      if (!w.disabled && w.running) {
        wl = w;
        break;
      }
    }
    MikrotikW60gLink? w60;
    for (final l in s.w60gLinks) {
      if (l.connected) {
        w60 = l;
        break;
      }
    }
    final wlMode = wl?.mode.toLowerCase() ?? '';
    final isAp = wl == null ? (w60 != null ? false : null) : (wlMode.contains('ap') || wlMode == 'bridge' || wlMode == 'wds-master');
    final upstream = isAp == false && s.wirelessClients.isNotEmpty ? s.wirelessClients.first : null;
    int? pos(int? v) => v != null && v > 0 ? v : null;
    final glance = DeviceGlance(
      uptimeSec: routerOsSeconds(s.uptime),
      peersKnown: detailed,
      cpu: s.cpuKnown ? s.cpuLoad : null,
      mem: s.memKnown ? s.memUsedPercent : null,
      temp: s.temperature,
      voltage: s.voltage,
      poeWatts: s.powerWatts,
      ppp: s.pppActiveCount > 0 ? s.pppActiveCount : null,
      signal: upstream != null && upstream.signalStrength != 0 ? upstream.signalStrength : w60?.rssi,
      snr: pos(upstream?.signalToNoise),
      ccq: upstream == null ? null : pos(upstream.txCcq) ?? pos(upstream.rxCcq),
      freqMhz: pos(wl?.frequency) ?? w60?.frequency,
      widthMhz: pos(wl?.channelWidth),
      distanceM: w60?.distanceMeters?.round(),
      // 60GHz: سرعة الربط باتّجاه الإرسال وحده (monitor) — لا رقم للاستقبال، لا نسخه.
      rxRateMbps: pos(upstream?.rxRate),
      txRateMbps: pos(upstream?.txRate) ?? w60?.phyRateMbps,
      ssid: (wl?.ssid.isNotEmpty ?? false) ? wl!.ssid : null,
      mode: wl?.mode,
      signalPct: w60?.signalPercent,
      isAp: isAp,
    );

    return ProbeResult(
      vitals: [
        // SNMP على SwOS لا يحمل المعالج والذاكرة ⇒ شرطةٌ لا صفر.
        if (s.cpuKnown)
          Vital(
            label: 'المعالج',
            value: '${s.cpuLoad}',
            unit: '٪',
            icon: LucideIcons.cpu,
            tone: Grade.percentLowerBetter(s.cpuLoad),
          )
        else
          Vital.empty.withIcon(LucideIcons.cpu),
        if (s.memKnown)
          Vital(
            label: 'الذاكرة',
            value: '${s.memUsedPercent}',
            unit: '٪',
            icon: LucideIcons.memoryStick,
            tone: Grade.percentLowerBetter(s.memUsedPercent),
          )
        else
          Vital.empty.withIcon(LucideIcons.memoryStick),
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
        peersLabel: s.w60gLinks.isNotEmpty && s.wirelessClients.isEmpty ? 'الطرف الآخر' : 'العملاء اللاسلكيّون',
        link: [
          for (final l in s.w60gLinks) ...[
            (k: 'وصلة ${l.iface}', v: l.connected ? 'متّصلة' : 'غير متّصلة'),
            if (l.rssi != null) (k: 'الإشارة', v: '${l.rssi} dBm'),
            if (l.signalPercent != null) (k: 'جودة الإشارة', v: '${l.signalPercent}%'),
            if (l.phyRateMbps != null) (k: 'سرعة الربط', v: MikrotikW60gLink.rateText(l.phyRateMbps!)),
            if (l.mcs != null) (k: 'MCS', v: '${l.mcs}'),
            if (l.distanceMeters != null) (k: 'المسافة', v: MikrotikW60gLink.distanceText(l.distanceMeters!)),
            if (l.frequency != null) (k: 'التردّد', v: '${l.frequency} MHz'),
          ],
        ],
        extras: [
          if (s.pppActiveCount > 0)
            (k: 'جلسات PPP', v: '${s.pppActiveCount}'),
          if (s.voltage != null)
            (k: 'الفولتيّة', v: '${s.voltage!.toStringAsFixed(1)} V'),
          if (s.powerWatts != null) (k: 'استهلاك PoE', v: '${s.powerWatts!.toStringAsFixed(1)} W'),
          if (s.currentAmps != null) (k: 'التيّار', v: '${s.currentAmps!.toStringAsFixed(1)} A'),
          if (s.fans.isNotEmpty) (k: 'المراوح', v: '${s.fans.length}'),
        ],
        glance: glance,
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
        physical: isWiredPortName(i.ifname),
      ));
    }

    final peers = [
      for (final st in s.stations)
        PeerLink(
          name: st.hostname?.isNotEmpty == true
              ? st.hostname!
              : (st.ip?.isNotEmpty == true ? st.ip! : st.mac),
          signal: st.signal,
          txSignal: st.txSignal != 0 ? st.txSignal : null,
          mac: st.mac,
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
          // airFiber X وWave: ما لا خانة له (تردّد الاستقبال، التعديل، القدرة، الاحتياطيّ…).
          ...s.extras,
        ],
        // نقطة الوصول (ap / ap-ptmp / ap-ptp) إشارتها عند محطّاتها؛ والمحطّة/airFiber إشارتها هي إشارة الوصلة.
        glance: DeviceGlance(
          uptimeSec: s.host.uptime > 0 ? s.host.uptime : null,
          peersKnown: true,
          cpu: s.host.cpuload,
          temp: s.host.temperature == 0 ? null : s.host.temperature,
          signal: (w == null || w.signal == 0) ? null : w.signal,
          noise: (w != null && w.hasNoise) ? w.noise : null,
          snr: w?.snr,
          ccq: (w != null && w.hasCcq) ? w.ccq : null,
          freqMhz: (w != null && w.frequency > 0) ? w.frequency : null,
          widthMhz: (w != null && w.chanbw > 0) ? w.chanbw : null,
          distanceM: (w != null && w.distance > 0) ? w.distance : null,
          rxRateMbps: (w != null && w.rxRate > 0) ? w.rxRate : null,
          txRateMbps: (w != null && w.txRate > 0) ? w.txRate : null,
          ssid: (w != null && w.essid.isNotEmpty) ? w.essid : null,
          mode: w?.mode,
          isAp: w?.mode.toLowerCase().startsWith('ap'),
        ),
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
      NetworkDevice d, Map<String, dynamic> creds, bool detailed) async {
    final community =
        (creds['community'] ?? creds['user'] ?? 'public').toString();
    final s = await MimosaApi.fetchStats(
      host: d.ip,
      port: d.apiPort ?? 161,
      community: community,
    );
    // سكتر PtMP (A5/C5 بوضع AP): محطّاته للبطاقة المفتوحة/الكبيرة وحدها — مسحتا SNMP إضافيّتان، والمطويّة تكتفي بالثلاثة.
    final isAp = s.wirelessMode == 1 ? true : (s.wirelessMode == 2 ? false : null);
    var clients = const <MimosaClient>[];
    var clientsRead = false;
    if (detailed && isAp == true) {
      try {
        clients = await MimosaApi.fetchClients(host: d.ip, port: d.apiPort ?? 161, community: community);
        clientsRead = true;
      } catch (_) {/* بلا محطّات — الخانات الثلاث تكفي */}
    }
    int? worst(Iterable<double?> xs, {required bool low}) {
      double? r;
      for (final x in xs) {
        if (x == null) continue;
        if (r == null || (low ? x < r : x > r)) r = x;
      }
      return r?.round();
    }
    int? freq;
    for (final c in s.chains) {
      if (c.centerFreqMhz != null && c.centerFreqMhz! > 0) {
        freq = c.centerFreqMhz;
        break;
      }
    }
    final glance = DeviceGlance(
      uptimeSec: s.linkUptimeSec,
      linkUptime: true,
      peersKnown: clientsRead,
      temp: s.temperatureC?.round(),
      signal: s.totalRxPowerDbm?.round(),
      // أسوأ سلسلة لا متوسّطها: سلسلةٌ ضعيفة تكفي لتكسر الوصلة.
      snr: worst(s.chains.map((c) => c.snrDb), low: true),
      noise: worst(s.chains.map((c) => c.rxNoiseDbm), low: false),
      freqMhz: freq,
      widthMhz: s.channelWidthMhz,
      rxRateMbps: s.phyRxRateMbps,
      txRateMbps: s.phyTxRateMbps,
      ssid: (s.ssid?.isNotEmpty ?? false) ? s.ssid : null,
      isAp: isAp,
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
                // إشارةٌ لاسلكيّة: سلّم الإشارة لا سلّم الضوء (‎-54 dBm وصلةٌ سليمة لا حمراء) — كلوحة ميموزا.
                tone: Grade.signal(s.totalRxPowerDbm),
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
        peers: [
          for (final c in clients)
            if (c.online)
              PeerLink(
                name: (c.name?.isNotEmpty ?? false) ? c.name! : ((c.ip?.isNotEmpty ?? false) ? c.ip! : c.mac),
                signal: c.rssiDbm,
                txRate: c.txRateMbps,
                rxRate: c.rxRateMbps,
                uptimeSec: c.uptimeSec,
              ),
        ],
        peersLabel: 'المحطّات',
        glance: glance,
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

/// أولت (VSOL أو BDCOM): مسحة البنية وحدها — الأسماء والحالة، بلا عدّادات
/// ولا عناوين (~١ث على ١٠٠ واجهة) — ومعالج BDCOM بحزمةٍ ثانية.
///
/// ⚡ والحمولة لقطة أولت كاملة البنية: تُحفظ في المخزن فتُفتح اللوحة
/// المفردة بالمشتركين ومنافذ PON فوراً، كما تُفتح لوحة ميكروتك بحمولة جدارها.
Future<ProbeResult> _olt(NetworkDevice d, Map<String, dynamic> creds, {bool detailed = false}) async {
  final community = (creds['community'] ?? creds['pass'] ?? '').toString().trim();
  if (community.isEmpty) throw StateError('أدخل الـcommunity');
  final port = d.apiPort ?? 161;
  var s = await VsolOltApi.fetchStats(
    host: d.ip,
    port: port,
    community: community,
    structureOnly: true,
    withCounters: false,
    withGponDetails: false,
    profile: OltProfile.fromDevice(d),
  );
  if (s.profile.readsBdcomEponTables || s.profile.readsHsgqTables) {
    final snmp = SnmpV2c(host: d.ip, port: port, community: community);
    final c = s.profile.readsHsgqTables ? await HsgqOlt.chassis(snmp.get) : await BdcomEpon.chassis(snmp);
    if (!c.isEmpty) s = s.copyWith(chassis: c);
  }
  // «الفحص الشامل» (٦ نوفمبر — المالك: «+ الاولتي… مفروض هم تظهرهن»): ضوء كلّ ONU متّصلة بمسح عموده (قارئ شبكة الألياف نفسه)
  var lights = const <OnuLight>[];
  if (detailed) {
    try {
      final snmp = SnmpV2c(host: d.ip, port: port, community: community);
      final rx = await OltFiberReads.rxColumn(snmp, s.profile, s.onus).timeout(const Duration(seconds: 25));
      if (rx != null) {
        lights = [
          for (final o in s.onus)
            if (o.online && rx[o.ifIndex] != null)
              OnuLight(
                name: (o.name ?? '').trim().isNotEmpty ? o.name!.trim() : (o.serial ?? o.mac ?? 'PON${o.ponPort}:${o.onuId}'),
                rx: rx[o.ifIndex]!,
                mac: o.mac,
              ),
        ]..sort((a, b) => a.rx.compareTo(b.rx));
      }
    } catch (_) {}
  }
  return oltProbeResult(s, lights: lights);
}

/// ضوء ONU واحدة (dBm) — لتقرير الأولت.
@immutable
class OnuLight {
  const OnuLight({required this.name, required this.rx, this.mac});
  final String name;
  final double rx;
  final String? mac;
}

/// خانات بطاقة الأولت وتفصيلها من لقطةٍ واحدة — الجدار وشاشات الألياف بالحساب نفسه ([bridgeFiberVitals]).
ProbeResult oltProbeResult(VsolOltStats s, {List<OnuLight> lights = const []}) {
  final cpu = s.chassis?.cpuPct;
  final pct = s.onusTotal == 0 ? null : s.onusOnline * 100 / s.onusTotal;
  return ProbeResult(
    vitals: [
      Vital(
        label: 'المشتركون',
        value: '${s.onusOnline}',
        unit: '/${s.onusTotal}',
        icon: LucideIcons.users,
        tone: pct == null ? AppTone.neutral : Grade.percentHigherBetter(pct),
      ),
      Vital(
        label: 'منافذ PON',
        value: '${s.ponUp}',
        unit: '/${s.ponPorts.length}',
        icon: LucideIcons.splitSquareVertical,
        tone: s.ponPorts.isEmpty
            ? AppTone.neutral
            : Grade.percentHigherBetter(s.ponUp * 100 / s.ponPorts.length),
      ),
      // BDCOM: المعالج. وVSOL بلا مجسّ معالجٍ في SNMP — مدّة التشغيل.
      if (cpu != null)
        Vital(
          label: 'المعالج',
          value: '$cpu',
          unit: '٪',
          icon: LucideIcons.cpu,
          tone: Grade.percentLowerBetter(cpu),
        )
      else if (s.uptime != null)
        Vital(
          label: 'التشغيل',
          value: DeviceVitals.fmtUptime(s.uptime!.inSeconds),
          icon: LucideIcons.clock,
          tone: AppTone.neutral,
        )
      else
        Vital.empty.withIcon(LucideIcons.cpu),
    ],
    detail: DeviceDetail(
      onuLights: lights,
      uptime: s.uptime == null ? null : DeviceVitals.fmtUptime(s.uptime!.inSeconds),
      model: s.profile.model,
      ports: [
        for (final u in s.uplinks) PortTraffic(name: u.name, up: u.up),
      ],
      extras: [
        for (final p in s.ponPorts) (k: p.label, v: '${p.onuOnline}/${p.onuTotal}'),
        if (s.chassis?.boxTempC != null) (k: 'الحرارة', v: '${s.chassis!.boxTempC}°C'),
        // الإجماليّ وحده — لا نسبة استخدام (used/free غير متوفّرين).
        if (s.chassis?.ramBytes != null)
          (k: 'الذاكرة', v: '${(s.chassis!.ramBytes! / (1024 * 1024)).round()} MB'),
      ],
      // لقطةٌ بلا بنية (لم يُقرأ شيء) ⇒ لا أعداد — «—» لا «0/0».
      glance: s.isEmpty
          ? const DeviceGlance()
          : DeviceGlance(
              uptimeSec: s.uptime?.inSeconds,
              cpu: cpu,
              temp: s.chassis?.boxTempC,
              onusOnline: s.onusOnline,
              onusTotal: s.onusTotal,
              pons: [for (final p in s.ponPorts) PonGlance(p.label, up: p.up, online: p.onuOnline, total: p.onuTotal)],
              uplinksUp: s.uplinks.where((u) => u.up).length,
              uplinksTotal: s.uplinks.length,
            ),
    ),
    counters: const {},
    raw: s.isEmpty ? null : s,
  );
}

/// شاشات الألياف تقرأ الأولت كلّ ١٥ث — قراءتها الحيّة تُكتب في مخزن القسم بخانات بطاقة الجدار نفسها، فلا يقول الجدار رقماً
/// والألياف غيره (المالك ٢٨ أكتوبر: «تتحدث مع تزامن تحديث الاجهزه»). معالج BDCOM/HSGQ لا تقرؤه الألياف: يُستعار من آخر لقطةٍ
/// حديثة للجدار/اللوحة، وإلّا لا كتابة (لا تُمحى خانة المعالج). يُستدعى من شاشات الألياف (مرّةً تكفي).
void bridgeFiberVitals() {
  FiberMonitor.onLiveStats ??= (int oltId, VsolOltStats s) {
    var st = s;
    if ((st.profile.readsBdcomEponTables || st.profile.readsHsgqTables) && st.chassis == null) {
      final prev = DeviceStatsCache.instance.seedFor<VsolOltStats>(oltId)?.chassis;
      if (prev == null || prev.isEmpty) return;
      st = st.copyWith(chassis: prev);
    }
    final r = oltProbeResult(st);
    DeviceStatsCache.instance.putVitals(oltId, r.vitals, r.detail);
  };
}

/// سسكو: جلسة CLI بلا `show interfaces` (≈٤٠ كيلوبايت) — المعالج والذاكرة
/// وحالة المنافذ. والتفصيل الكامل (العدّادات) للبطاقة المفتوحة وحدها.
Future<ProbeResult> _cisco(NetworkDevice d, Map<String, dynamic> creds, bool detailed) async {
  final user = (creds['user'] ?? '').toString();
  final pass = (creds['pass'] ?? '').toString();
  if (user.isEmpty) throw StateError('بيانات دخول ناقصة');
  final s = await CiscoApi.fetchStats(
    host: d.ip,
    user: user,
    pass: pass,
    port: d.apiPort ?? d.port,
    protocol: d.protocol ?? 'ssh',
    includeCounters: detailed,
  );
  final mem = s.memPercent;
  // «المنافذ» = الإيثرات (Fa/Gi/Te…) — لا Serial ولا ما لا يُعرف؛ جهازٌ لا يُعرف اسم منفذٍ فيه يبقى بمنافذ لوحته كلّها.
  final eth = [for (final i in s.physicalPorts) if (isWiredPortName(i.name)) i];
  final shownPorts = eth.isEmpty ? s.physicalPorts : eth;
  return ProbeResult(
    vitals: [
      s.cpuPercent == null
          ? Vital.empty.withIcon(LucideIcons.cpu)
          : Vital(
              label: 'المعالج',
              value: s.cpuPercent!.round().toString(),
              unit: '٪',
              icon: LucideIcons.cpu,
              tone: Grade.percentLowerBetter(s.cpuPercent),
            ),
      mem == null
          ? Vital.empty.withIcon(LucideIcons.memoryStick)
          : Vital(
              label: 'الذاكرة',
              value: mem.round().toString(),
              unit: '٪',
              icon: LucideIcons.memoryStick,
              tone: Grade.percentLowerBetter(mem),
            ),
      shownPorts.isEmpty
          ? Vital.empty.withIcon(LucideIcons.network)
          : Vital(
              label: 'المنافذ',
              value: '${shownPorts.where((i) => i.up).length}',
              unit: '/${shownPorts.length}',
              icon: LucideIcons.network,
              tone: AppTone.neutral,
            ),
    ],
    detail: DeviceDetail(
      uptime: s.uptime == null ? null : DeviceVitals.fmtUptime(s.uptime!.inSeconds),
      firmware: s.iosVersion,
      model: s.model,
      ports: [
        for (final i in s.physicalPorts)
          PortTraffic(
            name: i.shortName ?? i.name,
            up: i.up,
            // معدّل الخمس دقائق كما يحسبه الجهاز (show interfaces — القراءة المفصّلة): يصحّ من أوّل لقطة بلا فرق عدّادات.
            rxBps: i.rxBps,
            txBps: i.txBps,
            linkSpeed: i.speedMbps == null ? null : '${i.speedMbps}M',
            // الإيثرات وحدها (Fa/Gi/Te…) — لا Serial ولا ما لا يُعرف (المالك: «اهم شي الايثرات للسسكو»).
            physical: isWiredPortName(i.name),
          ),
      ],
      extras: [
        if (s.serial != null) (k: 'التسلسل', v: s.serial!),
      ],
      glance: DeviceGlance(uptimeSec: s.uptime?.inSeconds, cpu: s.cpuPercent?.round(), mem: mem?.round()),
    ),
    counters: const {},
    raw: s,
  );
}

/// روجي/ريي (SNMP): المعالج والذاكرة، والوصلة اللاسلكيّة (الإشارة) لجسرٍ،
/// أو المنافذ لسويتش/راوتر. والمرور من فارق العدّادات بين جلستين.
Future<ProbeResult> _ruijie(NetworkDevice d, Map<String, dynamic> creds, CounterSample? prev) async {
  final community = (creds['community'] ?? creds['pass'] ?? '').toString().trim();
  if (community.isEmpty) throw StateError('أدخل الـcommunity');
  final s = await RuijieApi.fetchStats(
    host: d.ip,
    port: d.apiPort ?? 161,
    community: community,
  );
  final counters = <String, ({int rx, int tx})>{};
  final ports = <PortTraffic>[];
  for (final i in s.ifaces) {
    counters[i.name] = (rx: i.rxBytes, tx: i.txBytes);
    final r = DeviceVitals._rate(i.name, i.rxBytes, i.txBytes, prev);
    ports.add(PortTraffic(
      name: i.name,
      up: i.operUp,
      rxBps: r.rx,
      txBps: r.tx,
      linkSpeed: i.speedMbps > 0 ? '${i.speedMbps}M' : null,
      physical: isWiredPortName(i.name),
    ));
  }
  final link = s.link;
  final up = s.ifaces.where((i) => i.operUp).length;
  return ProbeResult(
    vitals: [
      s.cpuPercent == null
          ? Vital.empty.withIcon(LucideIcons.cpu)
          : Vital(
              label: 'المعالج',
              value: s.cpuPercent!.round().toString(),
              unit: '٪',
              icon: LucideIcons.cpu,
              tone: Grade.percentLowerBetter(s.cpuPercent),
            ),
      s.memPercent == null
          ? Vital.empty.withIcon(LucideIcons.memoryStick)
          : Vital(
              label: 'الذاكرة',
              value: s.memPercent!.round().toString(),
              unit: '٪',
              icon: LucideIcons.memoryStick,
              tone: Grade.percentLowerBetter(s.memPercent),
            ),
      if (link != null && link.signalDbm != null)
        Vital(
          label: 'الإشارة',
          value: '${link.signalDbm}',
          unit: 'dBm',
          icon: LucideIcons.signal,
          tone: Grade.signal(link.signalDbm),
        )
      else if (s.ifaces.isNotEmpty)
        Vital(
          label: 'المنافذ',
          value: '$up',
          unit: '/${s.ifaces.length}',
          icon: LucideIcons.network,
          tone: AppTone.neutral,
        )
      else
        Vital.empty.withIcon(LucideIcons.network),
    ],
    detail: DeviceDetail(
      uptime: s.uptime == null ? null : DeviceVitals.fmtUptime(s.uptime!.inSeconds),
      model: s.sysName,
      ports: ports,
      link: [
        if (link?.ssid != null) (k: 'الوصلة', v: link!.ssid!),
        if (link?.snrDb != null) (k: 'SNR', v: '${link!.snrDb} dB'),
        if (link?.distanceM != null) (k: 'المسافة', v: '${link!.distanceM} m'),
      ],
      glance: DeviceGlance(
        uptimeSec: s.uptime?.inSeconds,
        cpu: s.cpuPercent?.round(),
        mem: s.memPercent?.round(),
        signal: link?.signalDbm,
        noise: link?.noiseDbm,
        snr: link?.snrDb,
        freqMhz: link?.freqMhz ?? link?.centerFreqMhz,
        distanceM: link?.distanceM,
        rxRateMbps: link?.rxRateMbps,
        txRateMbps: link?.txRateMbps,
        ssid: link?.ssid,
        isAp: link == null ? null : false,
      ),
    ),
    counters: counters,
    raw: s,
  );
}

/// اسم منفذ إيثرنت فعليّ (UBNT/روجي بلا نوع واجهة): eth0 · lan0 · GigabitEthernet 0/1 · Gi0/1 · Te1/0/1 · sfp1 · combo1 · Port 3
/// — لا جسر ولا VLAN ولا لاسلكيّ ولا نفق ولا جلسة PPP ولا إدارة/حلقة داخليّة.
bool isWiredPortName(String raw) {
  final n = raw.trim().toLowerCase();
  if (n.isEmpty) return false;
  const logical = ['vlan', 'br', 'bridge', 'wlan', 'ath', 'wifi', 'wl', 'ppp', 'l2tp', 'sstp', 'ovpn', 'pptp', 'tun', 'gre',
      'eoip', 'ipip', 'wg', 'lo', 'null', 'mgmt', 'manage', 'bond', 'veth', 'lte', 'cap', 'svi', 'dummy', 'sit', 'imq', 'ifb',
      'port-channel', 'virtual', 'dialer', 'async', 'bvi', 'nvi', 'multilink', 'cellular', 'appgigabit', 'embedded', 'vasi',
      'nve', 'serial', 'switch', 'vtun', 'ucse'];
  for (final p in logical) {
    if (n.startsWith(p)) return false;
  }
  // أسماء سسكو المختصرة للواجهات المنطقيّة: Po1 · Vl90 · Vi2.1 · Vt1 · Di1 · Tu0 · Nu0 · BV1 · Mu1 · Ap1/0/1 · Se0/0/0.
  if (RegExp(r'^(po|vl|vi|vt|di|tu|nu|bv|mu|ap|se)\d').hasMatch(n)) return false;
  return RegExp(r'^(eth|et\d|lan|wan|sfp|combo|qsfp|port|ge|xge|te|tw|fi|fo|hu|gi|fa|fe)').hasMatch(n);
}

/// مدّة تشغيل RouterOS بالثواني: «1w2d03:04:05» (API) · «9w4d» · «5h3m2s» · «03:04:05» — وغير المقروء null.
int? routerOsSeconds(String raw) {
  final r = raw.trim();
  if (r.isEmpty) return null;
  const unit = {'w': 604800, 'd': 86400, 'h': 3600, 'm': 60, 's': 1};
  var total = 0;
  var any = false;
  for (final m in RegExp(r'(\d+)(ms|w|d|h|m|s)').allMatches(r)) {
    final u = m.group(2)!;
    if (u == 'ms') continue;
    total += int.parse(m.group(1)!) * unit[u]!;
    any = true;
  }
  final hms = RegExp(r'(\d{1,3}):(\d{2}):(\d{2})').firstMatch(r);
  if (hms != null) {
    total += int.parse(hms.group(1)!) * 3600 + int.parse(hms.group(2)!) * 60 + int.parse(hms.group(3)!);
    any = true;
  }
  return any ? total : null;
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
