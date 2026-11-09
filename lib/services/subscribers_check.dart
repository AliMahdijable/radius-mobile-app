import 'package:easy_localization/easy_localization.dart' show StringTranslateExtension;
import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

import '../api/device_probe_api.dart';
import '../core/util/bidi.dart';
import '../core/util/format.dart';
import '../core/util/server_time.dart';
import '../models/device_health.dart';
import '../models/subscriber.dart';
import 'agent_net_presence.dart';
import 'connection_alerts.dart';
import 'merged_text.dart';
import 'vpn_now.dart';

/// مشكلة مشتركٍ في «الفحص العامّ»: نوعها وسطرها كما يُعرض.
typedef SubsCheckProblem = ({ConnectionProblemKind kind, String label});

/// قراءة مشتركٍ كما تُعرض في «الفحص العامّ» (٨ نوفمبر — المالك: «اظهار معلومات ال ccq كذلك»): كلّ مقاييسه لا المشكلة وحدها —
/// من الهاتف (قراءة الكارت نفسها) أو عبر الـVPN. الصفر ليس قراءة (كـ[ConnectionAlerts.detect]).
class SubsReading {
  const SubsReading({
    this.sig,
    this.ccq,
    this.lan,
    this.rx,
    this.temp,
    this.ms,
    this.device,
    this.via,
    this.at,
    this.vpn = false,
  });

  /// من فحص الخادم عبر الـVPN (لا من الهاتف).
  final bool vpn;

  /// الإشارة dBm (يوبيكويتي).
  final int? sig;

  /// جودة الربط ٪.
  final int? ccq;

  /// الكيبل: `unplugged` · `10` · `100` · `1000` (ميكا) · `on` (موصولٌ بسرعةٍ لا تُعرف) — null لم يُقرأ.
  final String? lan;

  /// ضوء الفايبر dBm وحرارة الوحدة °C.
  final double? rx;
  final double? temp;

  /// زمن الاستجابة (قراءة VPN بالبنك وحده).
  final int? ms;

  /// اسم الجهاز: اسم النانو أو طراز الوحدة.
  final String? device;

  /// من أين جاءت قراءة الـVPN حين لا تكون من جهازه: «السكتر» · «الأولت».
  final String? via;

  final DateTime? at;

  /// من لقطة الهاتف — null إن لم تحمل مقاييس (جهازٌ غير النانو والوحدة الضوئيّة).
  static SubsReading? ofSnapshot(DeviceHealthSnapshot? snap, DateTime at) {
    if (snap == null) return null;
    if (snap.kind == DeviceKind.ubiquiti && snap.ubnt != null) {
      final u = snap.ubnt!;
      final s = u.signalDbm;
      final c = u.ccqPercent;
      final h = u.hostname.trim();
      return SubsReading(
        sig: s != null && s < 0 ? s : null,
        ccq: c != null && c > 0 ? c : null,
        lan: lanOf(u),
        device: h.isEmpty ? null : h,
        at: at,
      );
    }
    if (snap.kind == DeviceKind.ont && snap.ont != null) {
      final o = snap.ont!;
      final rx = double.tryParse(o.rxPower);
      final t = double.tryParse(o.temperature);
      final m = o.model.trim();
      return SubsReading(
        rx: rx != null && rx < 0 ? rx : null,
        temp: t,
        device: m.isNotEmpty ? m : (o.vendor == 'zte' ? 'ZTE' : 'Huawei'),
        at: at,
      );
    }
    return null;
  }

  /// من فحص الخادم عبر الـVPN.
  static SubsReading ofVpn(VpnSubReading r, DateTime? at) {
    final s = r.sig;
    final c = r.ccq;
    final rx = r.rx;
    final lan = (r.lan ?? '').trim();
    return SubsReading(
      sig: s != null && s < 0 ? s : null,
      ccq: c != null && c > 0 ? c : null,
      lan: lan.isEmpty ? null : (lan == '0' ? 'unplugged' : lan),
      rx: rx != null && rx < 0 ? rx : null,
      temp: r.temp,
      ms: r.src == 'ping' ? r.ms : null,
      via: r.src == 'sector' ? 'السكتر' : (r.src == 'olt' ? 'الأولت' : null),
      at: at,
      vpn: true,
    );
  }

  /// كيبل النانو كما يُعرض — ومنطق «مفصول»/«10» نفسه في [ConnectionAlerts.lanState].
  static String? lanOf(UbiquitiStatus u) {
    if (u.lanPorts.isEmpty) return null;
    final p = u.primaryLan;
    if (p == null) return null;
    if (!p.plugged) return 'unplugged';
    if (p.speedUnknown) return 'on';
    final m = RegExp(r'^(\d+)Mbps').firstMatch(p.speed ?? '');
    final mbps = m == null ? null : int.tryParse(m.group(1)!);
    if (mbps == null) return 'on';
    return mbps == 0 ? 'unplugged' : '$mbps';
  }
}

/// مشتركٌ مقروء في التقرير — بمشاكله (فارغة = سليم) وقراءته.
class SubsCheckRow {
  const SubsCheckRow(this.sub, this.problems, {this.reading});
  final Subscriber sub;
  final List<SubsCheckProblem> problems;
  final SubsReading? reading;

  /// أسوأ مشاكله (الكيبل ثمّ الإشارة…) — null إن كان سليماً.
  ConnectionProblemKind? get worst {
    ConnectionProblemKind? w;
    for (final p in problems) {
      if (w == null || SubscribersCheck.order.indexOf(p.kind) < SubscribersCheck.order.indexOf(w)) w = p.kind;
    }
    return w;
  }
}

/// لماذا لم يُقرأ مشترك — وقسمه في الملخّص بـ[SubscribersCheck.catOf]. الترتيب ترتيب القائمة.
enum SubsMissWhy {
  /// عبر الـVPN: الخادم وصله ولا يجيب ⇒ «جهازه ما ردّ».
  dead,

  /// عبر الـVPN: يردّ (البنك) ولم تُقرأ مقاييسه — رمز جهازه، أو واجهته مقفولة (السطر في [SubsMissing] note). ٩ نوفمبر: كان «سليم».
  /// ⇒ «جهازه ما ردّ» بسببه.
  unmeasured,

  /// متّصلٌ وسُئل جهازه من شبكتك وما ردّ ⇒ «جهازه ما ردّ» (فحص الخادم المكتمل بلا قراءةٍ له صار [unchecked] — ١٠ نوفمبر).
  noReply,

  /// جهازه يردّ بلا مقاييس (ليس نانو ولا وحدةً ضوئيّة) ⇒ «بلا مقاييس».
  noMetrics,

  /// متّصلٌ ولم يصله الفحص: الجاري لم يبلغه بعد (note null)، أو لا فحص له أصلاً — بلا عنوان، أو لم يُفحص عبر الـVPN بعد، أو فحص
  /// الخادم اكتمل ولم يسأل جهازه ([SubscribersCheck.vpnUnreadNote]) (note)
  /// ⇒ «لم يُفحص». ١٠ نوفمبر: كان «لم يُقرأ — جهازه لم يردّ» ولم يُسأل جهازه.
  unchecked,

  /// «كل الشركات»: شركته لم تُفحص عبر الـVPN (بلا طريق، أو تعذّر) — السبب في [SubsMissing] note ⇒ «لم يُفحص».
  company,

  /// غير متّصلٍ الآن ولا قراءة له من هذا الفحص ⇒ «غير متّصل الآن» — ليس عطلاً بجهازه (١٠ نوفمبر: كان داخل «لم يُقرأ»).
  /// وقراءة هاتفٍ من قبل انقطاعه لا تُعدّ ([SubscribersCheck.currentFor]).
  offline,
}

typedef SubsMissing = ({Subscriber sub, SubsMissWhy why, String? note});

/// أقسام «الفحص العامّ» (١٠ نوفمبر — المالك مع صورة «قُرئ 58 من 113» و«لم يُقرأ 55»: «شنو علاقة العداد بالعدد مفروض العداد
/// يمثل الفحص هيج راح يبرك الوكيل»): المقروء بمشكلة أو سليم، والمتّصل الذي ما ردّ جهازه، ثمّ من لا يُقرأ أصلاً — غير المتّصل
/// (ليس عطلاً)، وجهازٌ بلا مقاييس، ومن لم يصله الفحص. الكلمات نفسها في الشاشة والتقرير المنسوخ وجواب الأمر الصوتيّ.
enum SubsCheckCat {
  problems('بمشكلة'),
  healthy('سليم'),
  noReply('جهازه ما ردّ'),
  offline('غير متّصل الآن'),
  noMetrics('بلا مقاييس'),
  unchecked('لم يُفحص');

  const SubsCheckCat(this.label);
  final String label;

  /// «لم يُفحص بعد» ما دام الفحص جارياً.
  String labelFor({bool running = false}) => this == unchecked && running ? 'لم يُفحص بعد' : label;
}

/// موجة فحص الهاتف كما يقرؤها «الفحص العامّ» (١٠ نوفمبر): جاريةٌ أم انتهت، وكم فُحص من كم — تقدّمها هي
/// ([DeviceProbeApi.warmProbe]) لا نسبة المقروء — ومن تشمل (من لم يبلغه دوره «لم يُفحص بعد» لا «ما ردّ»)، ومتى انتهت آخر موجة.
@immutable
class SubsWave {
  const SubsWave({
    this.running = false,
    this.done = 0,
    this.total = 0,
    this.startedAt,
    this.endedAt,
    this.keys = const {},
  });

  static const idle = SubsWave();

  final bool running;
  final int done;

  /// صفرٌ قبل أوّل نتيجة (تجهيز الإعدادات وقياس الخطّ) ⇒ «يفحص…» بلا عدد.
  final int total;
  final DateTime? startedAt;

  /// متى اكتملت آخر موجة — «انتهى الفحص» بوقته.
  final DateTime? endedAt;

  /// أهداف الموجة الجارية ([keyOf]).
  final Set<String> keys;

  static String keyOf(String? company, String username) => '${company ?? ''}|${username.trim().toLowerCase()}';

  bool covers(Subscriber s) => keys.contains(keyOf(s.companyKey, s.username));

  /// موجةٌ تبدأ لهؤلاء ([keyOf]) — وآخر انتهاءٍ محفوظ.
  SubsWave start(Iterable<String> targets, DateTime at) =>
      SubsWave(running: true, startedAt: at, endedAt: endedAt, keys: targets.toSet());

  SubsWave progress(int done, int total) =>
      SubsWave(running: running, done: done, total: total, startedAt: startedAt, endedAt: endedAt, keys: keys);

  SubsWave finish(DateTime at) => SubsWave(done: done, total: total, startedAt: startedAt, endedAt: at);

  /// لا شيء يحتاج الفحص (الكلّ طازج): الجارية — إن قطعتها هذه — تنتهي الآن، وإلّا كما هي.
  SubsWave settle(DateTime at) => running ? finish(at) : this;
}

/// [stopped]: فحص الخادم تُرك قبل أن يكمل (أُطفئ «وضع VPN» — رجع لشبكته) ⇒ يُقال، لا «انتهى» فحصٍ أقدم (المراجعة
/// F14/F22).
enum SubsRunState { running, finished, failed, stopped, idle }

/// شريط «الفحص العامّ»: الفحص نفسه لا نسبة المقروء (١٠ نوفمبر) — جارٍ «يفحص… 12 من 30»، ثمّ «انتهى الفحص — 113 مشترك»
/// بوقته والشريط ممتلئ (لا يبقى نصفاً بعد الانتهاء)، أو لماذا تعذّر، أو «لم يُفحص بعد».
@immutable
class SubsCheckProgress {
  const SubsCheckProgress(this.state, this.text, {this.value, this.at});
  final SubsRunState state;
  final String text;

  /// جارٍ: المفحوص ÷ المطلوب (null = غير محدّد)؛ انتهى: 1؛ غير ذلك null.
  final double? value;

  /// انتهى: وقت آخر فحص.
  final DateTime? at;

  bool get running => state == SubsRunState.running;
}

/// فحص الخادم عبر الـVPN كما يقرؤه الشريط ([SubscribersCheck.vpnRunOf]) — [stopped] سطر فحصٍ تُرك قبل أن يكمل.
typedef SubsVpnRun = ({bool busy, bool failed, String? line, int done, int total, double? value, String? stopped});

/// تقرير «الفحص العامّ» للمشتركين: من بمشكلة مصنّفين بنوعها، والسليم، ومن لم يُقرأ ولماذا — وأقسامه [SubsCheckCat].
class SubsCheckReport {
  const SubsCheckReport({
    required this.total,
    required this.read,
    required this.rows,
    this.healthy = const [],
    this.missing = const [],
    this.oldest,
    this.newest,
  });

  final int total;

  /// مشتركون لهم قراءةٌ معروفة (من الكارت/الذاكرة أو من فحص الـVPN).
  final int read;

  /// من بمشكلة — الأسوأ أوّلاً (الكيبل ثمّ الإشارة…، وداخل النوع الأشدّ).
  final List<SubsCheckRow> rows;

  /// المقروء بلا مشكلة — الأقرب للحدّ أوّلاً.
  final List<SubsCheckRow> healthy;

  /// من لم يُقرأ — الميّت عبر الـVPN أوّلاً ([SubsMissWhy] بترتيبه).
  final List<SubsMissing> missing;

  /// أقدم قراءة هاتفٍ داخلة وأحدثها — الأحدث وقت آخر فحصٍ حين لا تُعرف موجته.
  final DateTime? oldest;
  final DateTime? newest;

  int get unread => total - read;

  /// من بمشكلة بهذا النوع.
  List<SubsCheckRow> of(ConnectionProblemKind k) => [
        for (final r in rows)
          if (r.problems.any((p) => p.kind == k)) r
      ];

  /// من لم يُقرأ في القسم [c] (فارغة لـ«بمشكلة» و«سليم»).
  List<SubsMissing> missingIn(SubsCheckCat c) => [
        for (final m in missing)
          if (SubscribersCheck.catOf(m.why) == c) m
      ];

  /// عدد القسم [c].
  int count(SubsCheckCat c) => switch (c) {
        SubsCheckCat.problems => rows.length,
        SubsCheckCat.healthy => healthy.length,
        _ => missing.where((m) => SubscribersCheck.catOf(m.why) == c).length,
      };
}

/// «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك: «أ» ثمّ «تره فحص المشتركين ثكيل كلش مو مثل فحص الاجهزه ولا مثل مايعرضون
/// الاشارات وسرعته بكارت المشتركين»): خفيفٌ — من القراءات التي يعرضها كارت المشترك نفسه (ذاكرة الفحص، أيّ عمر)، والموجة تعيد
/// القديم وحده؛ والمشكلة بحدود «تنبيه المشترك» نفسها ([ConnectionAlerts.detect]) — لا تعريفٌ ثانٍ للضعيف. عبر الـVPN: قراءات
/// فحص الخادم ([VpnNow.readingFor]) بالحدود نفسها لكلّ شركة.
class SubscribersCheck {
  SubscribersCheck._();

  /// للاختبار: قراءات الهاتف بدل ذاكرة الفحص (الشاشة تنادي بلا [local]/[mixed] peek).
  @visibleForTesting
  static ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? Function(Subscriber s)? debugPeek;

  /// ترتيب الأنواع: الأسوأ أوّلاً.
  static const order = [
    ConnectionProblemKind.cable,
    ConnectionProblemKind.signal,
    ConnectionProblemKind.ccq,
    ConnectionProblemKind.fiberRx,
    ConnectionProblemKind.fiberTemp,
  ];

  /// داخل النوع الواحد: الأشدّ أوّلاً (المفصول قبل 10، الأضعف إشارةً، الأقلّ CCQ، الأضعف ضوءاً، الأسخن).
  static double _severity(SubsCheckRow r) {
    final x = r.reading;
    switch (r.worst) {
      case ConnectionProblemKind.cable:
        return x?.lan == 'unplugged' ? 0 : 1;
      case ConnectionProblemKind.signal:
        return (x?.sig ?? 0).toDouble();
      case ConnectionProblemKind.ccq:
        return (x?.ccq ?? 100).toDouble();
      case ConnectionProblemKind.fiberRx:
        return x?.rx ?? 0;
      case ConnectionProblemKind.fiberTemp:
        return -(x?.temp ?? 0);
      case null:
        return 0;
    }
  }

  static int _byWorst(SubsCheckRow a, SubsCheckRow b) {
    final k = order.indexOf(a.worst!).compareTo(order.indexOf(b.worst!));
    return k != 0 ? k : _severity(a).compareTo(_severity(b));
  }

  /// كم يبعد السليم عن حدّ المشكلة (بالديسيبل تقريباً) — الأقرب أوّلاً في قائمة «سليم».
  static double margin(SubsReading x, ConnectionAlertThresholds t) {
    var m = double.infinity;
    void take(double v) => m = v < m ? v : m;
    if (x.sig != null) take((x.sig! - t.signalDbm).toDouble());
    if (x.ccq != null) take((x.ccq! - t.ccqPct) / 2);
    if (x.rx != null) take(x.rx! - t.fiberRxDbm);
    if (x.temp != null) take((t.fiberTempC - x.temp!) / 2);
    return m;
  }

  static int _missRank(SubsMissing m) => SubsMissWhy.values.indexOf(m.why);

  /// فحص الخادم لشركته اكتمل ولا قراءة له ⇒ «لم يُفحص» بهذا السبب، لا «جهازه ما ردّ» (١٠ نوفمبر، فحص المحاكي: ١٦ من ١٣٣ متّصلاً
  /// بلا قراءة سُمّوا «ما ردّ»): الخادم يسأل أجهزة يوبيكويتي وحدها ويؤجّل رافض كلمة السرّ والساقط وبلا إدارة (connVpn
  /// targetsState.plan) — ومن سأله وما ردّ تأتي قراءته `dead` («لا يستجيب»)، فغياب القراءة يعني أنّ جهازه لم يُسأل.
  static const vpnUnreadNote = 'لم يُقرأ عبر VPN';

  /// قسم من لم يُقرأ.
  static SubsCheckCat catOf(SubsMissWhy why) => switch (why) {
        SubsMissWhy.dead || SubsMissWhy.unmeasured || SubsMissWhy.noReply => SubsCheckCat.noReply,
        SubsMissWhy.noMetrics => SubsCheckCat.noMetrics,
        SubsMissWhy.unchecked || SubsMissWhy.company => SubsCheckCat.unchecked,
        SubsMissWhy.offline => SubsCheckCat.offline,
      };

  /// سبب من لم يُقرأ بكلمات الوكيل — بجانب اسمه في الشاشة، وفي التقرير المنسوخ، وفي جواب الأمر الصوتيّ.
  static String missText(SubsMissing m, {bool running = false}) => switch (m.why) {
        SubsMissWhy.dead => 'لا يستجيب',
        SubsMissWhy.unmeasured => m.note ?? 'يردّ، ما انقرت مقاييسه',
        SubsMissWhy.noReply => m.note ?? 'ما ردّ من شبكتك',
        SubsMissWhy.noMetrics => 'جهازه بلا مقاييس',
        SubsMissWhy.unchecked => m.note ?? (running ? 'بانتظار الفحص' : 'لم يصله الفحص'),
        SubsMissWhy.company => (m.note ?? '').contains('تحتاج VPN')
            ? mergedWord('شركته تحتاج VPN', 'صفحته تحتاج VPN')
            : mergedWord('لم تُفحص شركته', 'لم تُفحص صفحته'),
        SubsMissWhy.offline => 'غير متّصل',
      };

  /// الفحص عبر الـVPN كما يقرؤه الشريط.
  static SubsVpnRun vpnRunOf(VpnNowJob j) => (
        busy: j.busy,
        failed: j.phase == VpnBarPhase.failed,
        line: j.line,
        done: j.done,
        total: j.total,
        value: j.value,
        stopped: j.stopped,
      );

  /// شريط الفحص (١٠ نوفمبر — المالك: «مفروض العداد يمثل الفحص»): [subs] مشتركو التقرير · [wave] موجة الهاتف (null: ليست من
  /// هذا الفحص) · [vpn] فحص الخادم (null: ليس منه) · [merged] «كل الشركات» و[vpnCompany] الشركة التي يفحصها الخادم الآن ·
  /// [at] متى اكتمل آخر فحص (الموجة، أو الخادم، أو أحدث قراءة).
  static SubsCheckProgress progress({
    required int subs,
    SubsWave? wave,
    SubsVpnRun? vpn,
    bool merged = false,
    String? vpnCompany,
    DateTime? at,
  }) {
    final w = wave;
    if (w != null && w.running) {
      final head = merged ? 'يفحص من شبكتك…' : 'يفحص…';
      if (w.total <= 0) return SubsCheckProgress(SubsRunState.running, head);
      return SubsCheckProgress(SubsRunState.running, '$head ${formatIQD(w.done)} من ${formatIQD(w.total)}',
          value: (w.done / w.total).clamp(0.0, 1.0));
    }
    final v = vpn;
    if (v != null && v.busy) {
      final named = merged && vpnCompany != null;
      if (v.total > 0) {
        return SubsCheckProgress(
            SubsRunState.running,
            // العدد أوّلاً: اسمٌ طويل يُقصّ ولا يُقصّ العدد
            'يفحص… ${formatIQD(v.done)} من ${formatIQD(v.total)}${named ? ' · «$vpnCompany» عبر VPN' : ''}',
            value: (v.done / v.total).clamp(0.0, 1.0));
      }
      // ما قبل الأجهزة وما بعدها (يتّصل، المتّصلون، السكترات، الأولت، يجمع النتيجة) — بكلمات شريط الـVPN نفسه
      return SubsCheckProgress(
          SubsRunState.running, named ? 'يفحص «$vpnCompany» عبر VPN…' : (v.line ?? 'يتّصل بالـVPN…'),
          value: v.value);
    }
    // فحص الخادم وحده تعذّر (لا موجة هاتفٍ معه) — سببه بكلماته
    if (v != null && v.failed && w == null) {
      return SubsCheckProgress(SubsRunState.failed, v.line ?? 'تعذّر الفحص الآن — حاول بعد قليل');
    }
    // وتُرك قبل أن يكمل (أُطفئ «وضع VPN») ⇒ يُقال — لا «انتهى الفحص» فحصٍ أقدم ولا «لم يُفحص بعد» (المراجعة F14/F22)
    if (v != null && v.stopped != null && w == null) return SubsCheckProgress(SubsRunState.stopped, v.stopped!);
    if (at == null) return const SubsCheckProgress(SubsRunState.idle, 'لم يُفحص بعد');
    return SubsCheckProgress(SubsRunState.finished, 'انتهى الفحص — ${formatIQD(subs)} مشترك', value: 1, at: at);
  }

  /// آخر سؤالٍ من الهاتف لأجهزة [subs] — ردّ أو ما ردّ، لا المقروء وحده: وقت «انتهى الفحص» حين لا تُعرف موجته (قائمةٌ
  /// فُتحت من جديد وقراءاتها طازجة فلا موجة) — أجهزةٌ سُئلت قبل دقائق لا تُقال «لم يُفحص بعد» (المراجعة F6).
  static DateTime? lastAsked(Iterable<Subscriber> subs) {
    final look = debugPeek ?? (s) => DeviceProbeApi.peek(username: s.username, ip: s.ipAddress, company: s.companyKey);
    DateTime? out;
    for (final s in subs) {
      final at = look(s)?.at;
      if (at != null && (out == null || at.isAfter(out))) out = at;
    }
    return out;
  }

  /// التقرير منسوخاً (١٠ نوفمبر) بأقسام الشاشة وكلماتها: سطر الفحص، ثمّ الأعداد، ثمّ من بمشكلة بمشاكله ومن ما ردّ جهازه ومن بلا
  /// مقاييس ومن لم يُفحص بأسبابهم — السليم وغير المتّصل عددٌ وحده (لا عطل يُتابَع). [companyOf] «كل الشركات»: اسم شركة
  /// المشترك، و[companies] سطر كلّ شركةٍ كبطاقة «الشركات» — طريقها وعمر قراءاتها (المراجعة F15: لا يُختم الكلّ بوقت
  /// أحدث الطرق).
  static String reportText(
    SubsCheckReport r, {
    required SubsCheckProgress progress,
    String? source,
    String? Function(Subscriber s)? companyOf,
    List<({String name, String text})> companies = const [],
  }) {
    final running = progress.running;
    final at = progress.at;
    final out = <String>[
      'الفحص العامّ للمشتركين${source == null ? '' : ' — $source'}',
      running ? '${progress.text} — لم يكتمل' : (at == null ? progress.text : '${progress.text} · ${timeAgoAr(at)}'),
      [
        for (final c in SubsCheckCat.values)
          if (c == SubsCheckCat.problems || c == SubsCheckCat.healthy || r.count(c) > 0)
            '${c.labelFor(running: running)} ${formatIQD(r.count(c))}',
      ].join(' · '),
    ];
    if (companies.isNotEmpty) {
      out
        ..add('')
        ..add('${mergedWord('الشركات', 'الصفحات')}:');
      for (final c in companies) {
        out.add('• ${c.name} — ${c.text}');
      }
    }
    String who(Subscriber s) {
      final name = s.fullName.trim().isEmpty ? s.username : s.fullName.trim();
      final co = companyOf?.call(s);
      return '$name (${s.username}${co == null ? '' : ' · $co'})';
    }

    if (r.rows.isNotEmpty) {
      out
        ..add('')
        ..add('${SubsCheckCat.problems.label} (${formatIQD(r.rows.length)}):');
      for (final row in r.rows) {
        out.add('• ${who(row.sub)} — ${row.problems.map((p) => p.label).join(' · ')}');
      }
    }
    for (final c in const [SubsCheckCat.noReply, SubsCheckCat.noMetrics, SubsCheckCat.unchecked]) {
      final ms = r.missingIn(c);
      if (ms.isEmpty) continue;
      out
        ..add('')
        ..add('${c.labelFor(running: running)} (${formatIQD(ms.length)}):');
      for (final m in ms) {
        final why = missText(m, running: running);
        out.add('• ${who(m.sub)}${why == c.label ? '' : ' — $why'}');
      }
    }
    return out.join('\n');
  }

  static SubsCheckReport _report(
    int total,
    List<SubsCheckRow> rows,
    List<SubsCheckRow> healthy,
    List<SubsMissing> missing,
    ConnectionAlertThresholds Function(String? company) limits, {
    DateTime? oldest,
    DateTime? newest,
  }) {
    rows.sort(_byWorst);
    final margins = <SubsCheckRow, double>{
      for (final h in healthy) h: h.reading == null ? double.infinity : margin(h.reading!, limits(h.sub.companyKey)),
    };
    healthy.sort((a, b) => margins[a]!.compareTo(margins[b]!));
    // داخل السبب الواحد بترتيب القائمة نفسه (sort في Dart غير مستقرّ — كانت الصفوف تتقافز: 76، 71، 72…)
    final order = List<int>.generate(missing.length, (i) => i)
      ..sort((a, b) {
        final k = _missRank(missing[a]).compareTo(_missRank(missing[b]));
        return k != 0 ? k : a.compareTo(b);
      });
    final sortedMissing = [for (final i in order) missing[i]];
    return SubsCheckReport(
      total: total,
      read: rows.length + healthy.length,
      rows: rows,
      healthy: healthy,
      missing: sortedMissing,
      oldest: oldest,
      newest: newest,
    );
  }

  /// لم يبلغه الفحص الجاري بعد: من أهداف الموجة، ولا نتيجة له منذ بدأت.
  static bool _awaitsWave(Subscriber s, ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? p, SubsWave? w) {
    if (w == null || !w.running || !w.covers(s)) return false;
    final from = w.startedAt;
    return p == null || from == null || p.at.isBefore(from);
  }

  /// من لا قراءة بمقاييس له من الهاتف: غير المتّصل أوّلاً (ليس عطلاً)، ثمّ من لم تبلغه الموجة الجارية، ثمّ جهازٌ ردّ بلا مقاييس،
  /// أو فُحص وما ردّ، أو لم يُفحص أصلاً (بلا عنوان).
  static SubsMissing _missLocal(Subscriber s, ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? p, SubsWave? w) {
    if (!s.isOnline) return (sub: s, why: SubsMissWhy.offline, note: null);
    if (_awaitsWave(s, p, w)) return (sub: s, why: SubsMissWhy.unchecked, note: null);
    if (p?.snap != null) return (sub: s, why: SubsMissWhy.noMetrics, note: null);
    if (p != null) return (sub: s, why: SubsMissWhy.noReply, note: null);
    return (sub: s, why: SubsMissWhy.unchecked, note: _noAddress(s));
  }

  /// لا عنوان من الراديوس ولا نتيجة فحص ⇒ الموجة لم تسأل جهازه (المحفوظ يدويّاً يُفحص ويُقرأ باسمه).
  static String? _noAddress(Subscriber s) => (s.ipAddress ?? '').trim().isEmpty ? 'بلا عنوان IP' : null;

  /// قراءة الهاتف [p] تُعدّ للمشترك في هذا الفحص؟ المتّصل: بأيّ عمر كما كانت (الموجة تعيد القديم). وغير المتّصل
  /// الآن: إن كانت من هذا الفحص — طازجةً (دون مهلة ذاكرة الفحص، بعدها تعيدها الموجة) أو من الموجة الجارية أو الأخيرة
  /// [w] — فالمطفأ يُفحص عمداً (جهاز وصوله قد يكون حيّاً) وقراءته من الفحص تُعدّ كما هي. وإلّا فهي من قبل انقطاعه:
  /// ذاكرة الفحص لا تُمحى بانقطاعه، وبلا عنوانٍ لا تعيدها الموجة ⇒ «غير متّصل الآن» لا «سليم»/«بمشكلة» بقراءةٍ
  /// عمرها ساعات (المراجعة ١٠ نوفمبر). قراءة الـVPN لا تمرّ هنا: عمرها حدّه ٣٠ دقيقة ([VpnNow.readingFor]) للمتّصل
  /// وغيره.
  static bool currentFor(Subscriber s, ({DeviceHealthSnapshot? snap, bool stale, DateTime at}) p, SubsWave? w) {
    if (s.isOnline || !p.stale) return true;
    final from = w?.startedAt;
    return from != null && !p.at.isBefore(from);
  }

  /// من قراءات الهاتف (الكارت): [peek] يُستبدل في الاختبار، و[wave] الموجة الجارية (من لم تبلغه «لم يُفحص بعد»)؛ وغير
  /// المتّصل الآن بقراءةٍ من قبل هذا الفحص «غير متّصل الآن» ([currentFor]).
  static SubsCheckReport local(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? Function(Subscriber s)? peek,
    SubsWave? wave,
  }) {
    final look =
        peek ?? debugPeek ?? (s) => DeviceProbeApi.peek(username: s.username, ip: s.ipAddress, company: s.companyKey);
    DateTime? oldest;
    DateTime? newest;
    final rows = <SubsCheckRow>[];
    final healthy = <SubsCheckRow>[];
    final missing = <SubsMissing>[];
    for (final s in subs) {
      final p = look(s);
      final snap = p?.snap;
      // قراءةٌ بمقاييس (يوبيكويتي أو ONT) وحدها — جهازٌ آخر بلا أرقام ليس «مقروءاً»
      final x = p == null ? null : SubsReading.ofSnapshot(snap, p.at);
      if (x == null) {
        missing.add(_missLocal(s, p, wave));
        continue;
      }
      // غير المتّصل الآن بقراءةٍ من قبل هذا الفحص ⇒ «غير متّصل الآن» لا قسمها ([currentFor])
      if (!currentFor(s, p!, wave)) {
        missing.add((sub: s, why: SubsMissWhy.offline, note: null));
        continue;
      }
      if (oldest == null || p.at.isBefore(oldest)) oldest = p.at;
      if (newest == null || p.at.isAfter(newest)) newest = p.at;
      final probs = ConnectionAlerts.detect(snap!, limits(s.companyKey));
      final row = SubsCheckRow(s, [for (final q in probs) (kind: q.kind, label: q.label)], reading: x);
      (probs.isEmpty ? healthy : rows).add(row);
    }
    return _report(subs.length, rows, healthy, missing, limits, oldest: oldest, newest: newest);
  }

  /// من قراءات فحص الخادم عبر الـVPN: [reading] يُستبدل في الاختبار، و[readAt] وقت فحص شركة المشترك (null: لم تُفحص)،
  /// و[running] فحص الخادم جارٍ (من لا قراءة له «لم يُفحص بعد» لا «ما ردّ»).
  static SubsCheckReport vpn(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    VpnSubReading? Function(Subscriber s)? reading,
    DateTime? Function(String? company)? readAt,
    bool? running,
  }) {
    final look = reading ?? (s) => VpnNow.readingFor(s.username, company: s.companyKey);
    final when = readAt ?? (c) => VpnNow.readingsAtFor(c) ?? VpnNow.readingsAt;
    final busy = running ?? VpnNow.subscribers.busy;
    final rows = <SubsCheckRow>[];
    final healthy = <SubsCheckRow>[];
    final missing = <SubsMissing>[];
    for (final s in subs) {
      final r = look(s);
      // ٩ نوفمبر: يردّ بلا مقاييس (البنك وحده) ⇒ «لم يُقرأ» بسببه — لا «سليم» (خادمٌ قديم أو جديد سواء)
      if (r == null || r.dead || !r.measured) {
        missing.add(_missVpn(s, r, busy: busy, checkedAt: when(s.companyKey)));
        continue;
      }
      final probs = fromVpn(r, limits(s.companyKey));
      final row = SubsCheckRow(s, probs, reading: SubsReading.ofVpn(r, when(s.companyKey)));
      (probs.isEmpty ? healthy : rows).add(row);
    }
    return _report(subs.length, rows, healthy, missing, limits);
  }

  /// من لا قراءة بمقاييس له عبر الـVPN: غير المتّصل أوّلاً، ثمّ من لا نتيجة له (الفحص جارٍ ⇒ لم يبلغه بعد؛ لا فحص مكتمل ⇒ لم
  /// يُفحص؛ فحصٌ مكتمل بلا قراءةٍ له ⇒ لم يُفحص [vpnUnreadNote])، ثمّ الميّت، ومن يردّ بلا مقاييس.
  static SubsMissing _missVpn(Subscriber s, VpnSubReading? r, {required bool busy, required DateTime? checkedAt}) {
    if (!s.isOnline) return (sub: s, why: SubsMissWhy.offline, note: null);
    if (r == null) {
      if (busy) return (sub: s, why: SubsMissWhy.unchecked, note: null);
      if (checkedAt == null) return (sub: s, why: SubsMissWhy.unchecked, note: 'لم يُفحص عبر VPN بعد');
      return (sub: s, why: SubsMissWhy.unchecked, note: vpnUnreadNote);
    }
    if (r.dead) return (sub: s, why: SubsMissWhy.dead, note: null);
    return unmeasured(s, r);
  }

  /// «كل الشركات» (٨ نوفمبر — المالك: «فحص المشتركين… مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم… ايرث لنك رابطلها vpn
  /// والسوبرنت تشتغل لوكل»): كلّ مشتركٍ بأحدث قراءةٍ له — من الهاتف (جهازه وصله موبايلك) أو من فحص شركته عبر الـVPN؛ ومن لم يُقرأ
  /// وشركته لم تُفحص عبر الـVPN يُقال سببها ([companyNote]: ««ايرث لنك» تحتاج VPN»…).
  ///
  /// ١٠ نوفمبر: [wave] موجة الهاتف الجارية و[vpnWaits] شركةٌ يفحصها الخادم الآن أو بعد قليل — من لم يبلغه أيٌّ منهما «لم يُفحص
  /// بعد» لا «ما ردّ»؛ وغير المتّصل وحده قسمه.
  static SubsCheckReport mixed(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? Function(Subscriber s)? peek,
    VpnSubReading? Function(Subscriber s)? reading,
    DateTime? Function(String? company)? readAt,
    String? Function(String? company)? companyNote,
    SubsWave? wave,
    bool Function(String? company)? vpnWaits,
    bool Function(String? company)? localFailsFor,
  }) {
    final look =
        peek ?? debugPeek ?? (s) => DeviceProbeApi.peek(username: s.username, ip: s.ipAddress, company: s.companyKey);
    // فشل فحص الهاتف شهادةٌ على جهازه وهو على الشبكة وحده (كالأمر الصوتيّ): خارجها أو بـ«وضع VPN» لا يصل الهاتف شيئاً، فـ«ما ردّ من
    // شبكتك» كاذبة (١٠ نوفمبر، المحاكي خارج الشبكة) — والشاشة تحصره بشركةٍ تُقرأ من شبكتك (المفتوحة): غيرها طريقه VPN شركته.
    // القراءة الناجحة تبقى قراءةً من أيّ مكان.
    final onNet = !VpnNow.mode.value && !AgentNetPresence.isOff;
    final localFails = localFailsFor ?? ((_) => onNet);
    final vpnLook = reading ?? (s) => VpnNow.readingFor(s.username, company: s.companyKey);
    final when = readAt ?? (c) => c == null ? VpnNow.readingsAt : VpnNow.readingsAtFor(c);
    final waits = vpnWaits ?? (c) => c != null && VpnNow.subscribers.waits(c);
    DateTime? oldest;
    DateTime? newest;
    final rows = <SubsCheckRow>[];
    final healthy = <SubsCheckRow>[];
    final missing = <SubsMissing>[];
    for (final s in subs) {
      final p = look(s);
      // غير المتّصل الآن بقراءة هاتفٍ من قبل هذا الفحص ⇒ لا تُعدّ ([currentFor])
      final local = p == null || !currentFor(s, p, wave) ? null : SubsReading.ofSnapshot(p.snap, p.at);
      final v = vpnLook(s);
      final checkedAt = when(s.companyKey);
      final vAt = v == null ? null : checkedAt;
      final t = limits(s.companyKey);
      // الأحدث يغلب: قراءة الـVPN إن لم تكن قراءة الهاتف أو كانت أقدم منها — وبمقاييس (البنك وحده لا يغلب قراءةً حقيقيّة)
      final useVpn = v != null && !v.dead && v.measured && (local == null || (vAt != null && vAt.isAfter(p!.at)));
      if (useVpn) {
        final probs = fromVpn(v, t);
        (probs.isEmpty ? healthy : rows).add(SubsCheckRow(s, probs, reading: SubsReading.ofVpn(v, vAt)));
        continue;
      }
      if (local != null) {
        if (oldest == null || p!.at.isBefore(oldest)) oldest = p!.at;
        if (newest == null || p.at.isAfter(newest)) newest = p.at;
        final probs = ConnectionAlerts.detect(p.snap!, t);
        (probs.isEmpty ? healthy : rows)
            .add(SubsCheckRow(s, [for (final q in probs) (kind: q.kind, label: q.label)], reading: local));
        continue;
      }
      if (!s.isOnline) {
        missing.add((sub: s, why: SubsMissWhy.offline, note: null));
        continue;
      }
      // يردّ عبر الـVPN بلا مقاييس ولا قراءة هاتف ⇒ «لم يُقرأ» بسببه
      if (v != null && !v.dead && p?.snap == null) {
        missing.add(unmeasured(s, v));
        continue;
      }
      if (_awaitsWave(s, p, wave) || (v == null && waits(s.companyKey))) {
        missing.add((sub: s, why: SubsMissWhy.unchecked, note: null));
        continue;
      }
      final note = companyNote?.call(s.companyKey);
      missing.add(v != null && v.dead
          ? (sub: s, why: SubsMissWhy.dead, note: null)
          : note != null
              ? (sub: s, why: SubsMissWhy.company, note: note)
              : p?.snap != null
                  ? (sub: s, why: SubsMissWhy.noMetrics, note: null)
                  : p != null && localFails(s.companyKey)
                      ? (sub: s, why: SubsMissWhy.noReply, note: null)
                      // فحص الخادم لشركته اكتمل بلا قراءةٍ له ⇒ لم يُسأل جهازه ([vpnUnreadNote])؛ ولا فحص له بأيّ طريق ⇒ لم يُفحص
                      : checkedAt != null
                          ? (sub: s, why: SubsMissWhy.unchecked, note: vpnUnreadNote)
                          : (sub: s, why: SubsMissWhy.unchecked, note: _noAddress(s)));
    }
    return _report(subs.length, rows, healthy, missing, limits, oldest: oldest, newest: newest);
  }

  /// قراءة VPN بلا مقاييس ⇒ سطر من لم يُقرأ: البنك وحده ⇒ «يردّ» بسببه إن أعطاه الخادم («جهازه ما ردّ»)؛ وجهازٌ قُرئ بلا أرقام ⇒
  /// «بلا مقاييس». وجواب الأمر الصوتيّ به كذلك.
  static SubsMissing unmeasured(Subscriber s, VpnSubReading r) => r.src == 'ping'
      ? (sub: s, why: SubsMissWhy.unmeasured, note: unmeasuredLabel(r))
      : (sub: s, why: SubsMissWhy.noMetrics, note: null);

  /// «يردّ، ما انقرت مقاييسه» — وبسببه من خادمٍ يعطيه (`err`).
  static String unmeasuredLabel(VpnSubReading r) => switch (r.err) {
        'login_failed' => 'يردّ، ما انفتح برمزه المحفوظ',
        'no_web' => 'يردّ، واجهة إدارته ما تفتح',
        _ => 'يردّ، ما انقرت مقاييسه',
      };

  /// قراءة الخادم ⇒ المشاكل بحدود المدير — كـ[ConnectionAlerts.detect] حرفاً (الصفر ليس قراءة).
  static List<SubsCheckProblem> fromVpn(VpnSubReading r, ConnectionAlertThresholds t) {
    final out = <SubsCheckProblem>[];
    if (r.lan == 'unplugged') {
      out.add((kind: ConnectionProblemKind.cable, label: 'conn_alerts.p_lan_unplugged'.tr()));
    } else if (r.lan == '10') {
      out.add((kind: ConnectionProblemKind.cable, label: 'conn_alerts.p_lan_10'.tr()));
    }
    final s = r.sig;
    if (s != null && s < 0 && s < t.signalDbm) {
      out.add((kind: ConnectionProblemKind.signal, label: 'conn_alerts.p_signal'.tr(args: [iso('$s dBm')])));
    }
    final c = r.ccq;
    if (c != null && c > 0 && c <= t.ccqPct) {
      out.add((kind: ConnectionProblemKind.ccq, label: 'conn_alerts.p_ccq'.tr(args: [iso('$c%')])));
    }
    final rx = r.rx;
    if (rx != null && rx < 0 && rx < t.fiberRxDbm) {
      out.add((
        kind: ConnectionProblemKind.fiberRx,
        label: 'conn_alerts.p_fiber_rx'.tr(args: [iso('${rx.toStringAsFixed(1)} dBm')])
      ));
    }
    final temp = r.temp;
    if (temp != null && temp > t.fiberTempC) {
      out.add((
        kind: ConnectionProblemKind.fiberTemp,
        label: 'conn_alerts.p_fiber_temp'.tr(args: [iso('${temp.toStringAsFixed(0)}°C')])
      ));
    }
    return out;
  }
}
