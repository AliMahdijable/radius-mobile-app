import 'package:easy_localization/easy_localization.dart' show StringTranslateExtension;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../api/device_probe_api.dart';
import '../core/util/bidi.dart';
import '../models/device_health.dart';
import '../models/subscriber.dart';
import 'connection_alerts.dart';
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

/// لماذا لم يُقرأ مشترك.
enum SubsMissWhy {
  /// عبر الـVPN: الخادم وصله ولا يجيب.
  dead,

  /// «كل الشركات»: شركته لم تُفحص عبر الـVPN (بلا طريق، أو تعذّر) — السبب في [SubsMissing] note.
  company,

  /// غير متّصلٍ الآن.
  offline,

  /// متّصلٌ ولا قراءة له (جهازه لا يردّ، أو بلا عنوان، أو لم يصله الفحص بعد).
  noReply,

  /// جهازه يُقرأ بلا مقاييس (ليس نانو ولا وحدةً ضوئيّة).
  noMetrics,
}

typedef SubsMissing = ({Subscriber sub, SubsMissWhy why, String? note});

/// تقرير «الفحص العامّ» للمشتركين: كم قُرئ من كم، ومن بمشكلة مصنّفين بنوعها، والسليم، ومن لم يُقرأ ولماذا.
class SubsCheckReport {
  const SubsCheckReport({
    required this.total,
    required this.read,
    required this.rows,
    this.healthy = const [],
    this.missing = const [],
    this.oldest,
  });

  final int total;

  /// مشتركون لهم قراءةٌ معروفة (من الكارت/الذاكرة أو من فحص الـVPN).
  final int read;

  /// من بمشكلة — الأسوأ أوّلاً (الكيبل ثمّ الإشارة…، وداخل النوع الأشدّ).
  final List<SubsCheckRow> rows;

  /// المقروء بلا مشكلة — الأقرب للحدّ أوّلاً.
  final List<SubsCheckRow> healthy;

  /// من لم يُقرأ — الميّت عبر الـVPN أوّلاً.
  final List<SubsMissing> missing;

  /// أقدم قراءةٍ داخلة (للسطر «آخر قراءة قبل…»).
  final DateTime? oldest;

  int get unread => total - read;

  /// من بمشكلة بهذا النوع.
  List<SubsCheckRow> of(ConnectionProblemKind k) => [
        for (final r in rows)
          if (r.problems.any((p) => p.kind == k)) r
      ];
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

  static SubsCheckReport _report(
    int total,
    List<SubsCheckRow> rows,
    List<SubsCheckRow> healthy,
    List<SubsMissing> missing,
    ConnectionAlertThresholds Function(String? company) limits, {
    DateTime? oldest,
  }) {
    rows.sort(_byWorst);
    final margins = <SubsCheckRow, double>{
      for (final h in healthy) h: h.reading == null ? double.infinity : margin(h.reading!, limits(h.sub.companyKey)),
    };
    healthy.sort((a, b) => margins[a]!.compareTo(margins[b]!));
    missing.sort((a, b) => _missRank(a).compareTo(_missRank(b)));
    return SubsCheckReport(
      total: total,
      read: rows.length + healthy.length,
      rows: rows,
      healthy: healthy,
      missing: missing,
      oldest: oldest,
    );
  }

  /// من قراءات الهاتف (الكارت): [peek] يُستبدل في الاختبار.
  static SubsCheckReport local(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? Function(Subscriber s)? peek,
  }) {
    final look =
        peek ?? debugPeek ?? (s) => DeviceProbeApi.peek(username: s.username, ip: s.ipAddress, company: s.companyKey);
    DateTime? oldest;
    final rows = <SubsCheckRow>[];
    final healthy = <SubsCheckRow>[];
    final missing = <SubsMissing>[];
    for (final s in subs) {
      final p = look(s);
      final snap = p?.snap;
      // قراءةٌ بمقاييس (يوبيكويتي أو ONT) وحدها — جهازٌ آخر بلا أرقام ليس «مقروءاً»
      final x = p == null ? null : SubsReading.ofSnapshot(snap, p.at);
      if (x == null) {
        missing.add((
          sub: s,
          why: snap != null ? SubsMissWhy.noMetrics : (s.isOnline ? SubsMissWhy.noReply : SubsMissWhy.offline),
          note: null,
        ));
        continue;
      }
      if (oldest == null || p!.at.isBefore(oldest)) oldest = p!.at;
      final probs = ConnectionAlerts.detect(snap!, limits(s.companyKey));
      final row = SubsCheckRow(s, [for (final q in probs) (kind: q.kind, label: q.label)], reading: x);
      (probs.isEmpty ? healthy : rows).add(row);
    }
    return _report(subs.length, rows, healthy, missing, limits, oldest: oldest);
  }

  /// من قراءات فحص الخادم عبر الـVPN: [reading] يُستبدل في الاختبار، و[readAt] وقت فحص شركة المشترك.
  static SubsCheckReport vpn(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    VpnSubReading? Function(Subscriber s)? reading,
    DateTime? Function(String? company)? readAt,
  }) {
    final look = reading ?? (s) => VpnNow.readingFor(s.username, company: s.companyKey);
    final when = readAt ?? (c) => VpnNow.readingsAtFor(c) ?? VpnNow.readingsAt;
    final rows = <SubsCheckRow>[];
    final healthy = <SubsCheckRow>[];
    final missing = <SubsMissing>[];
    for (final s in subs) {
      final r = look(s);
      if (r == null || r.dead) {
        missing.add((
          sub: s,
          why: r != null ? SubsMissWhy.dead : (s.isOnline ? SubsMissWhy.noReply : SubsMissWhy.offline),
          note: null,
        ));
        continue;
      }
      final probs = fromVpn(r, limits(s.companyKey));
      final row = SubsCheckRow(s, probs, reading: SubsReading.ofVpn(r, when(s.companyKey)));
      (probs.isEmpty ? healthy : rows).add(row);
    }
    return _report(subs.length, rows, healthy, missing, limits);
  }

  /// «كل الشركات» (٨ نوفمبر — المالك: «فحص المشتركين… مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم… ايرث لنك رابطلها vpn
  /// والسوبرنت تشتغل لوكل»): كلّ مشتركٍ بأحدث قراءةٍ له — من الهاتف (جهازه وصله موبايلك) أو من فحص شركته عبر الـVPN؛ ومن لم يُقرأ
  /// وشركته لم تُفحص عبر الـVPN يُقال سببها ([companyNote]: ««ايرث لنك» تحتاج VPN»…).
  static SubsCheckReport mixed(
    List<Subscriber> subs,
    ConnectionAlertThresholds Function(String? company) limits, {
    ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? Function(Subscriber s)? peek,
    VpnSubReading? Function(Subscriber s)? reading,
    DateTime? Function(String? company)? readAt,
    String? Function(String? company)? companyNote,
  }) {
    final look =
        peek ?? debugPeek ?? (s) => DeviceProbeApi.peek(username: s.username, ip: s.ipAddress, company: s.companyKey);
    final vpnLook = reading ?? (s) => VpnNow.readingFor(s.username, company: s.companyKey);
    final when = readAt ?? (c) => c == null ? VpnNow.readingsAt : VpnNow.readingsAtFor(c);
    DateTime? oldest;
    final rows = <SubsCheckRow>[];
    final healthy = <SubsCheckRow>[];
    final missing = <SubsMissing>[];
    for (final s in subs) {
      final p = look(s);
      final local = p == null ? null : SubsReading.ofSnapshot(p.snap, p.at);
      final v = vpnLook(s);
      final vAt = v == null ? null : when(s.companyKey);
      final t = limits(s.companyKey);
      // الأحدث يغلب: قراءة الـVPN إن لم تكن قراءة الهاتف أو كانت أقدم منها
      final useVpn = v != null && !v.dead && (local == null || (vAt != null && vAt.isAfter(p!.at)));
      if (useVpn) {
        final probs = fromVpn(v, t);
        (probs.isEmpty ? healthy : rows).add(SubsCheckRow(s, probs, reading: SubsReading.ofVpn(v, vAt)));
        continue;
      }
      if (local != null) {
        if (oldest == null || p!.at.isBefore(oldest)) oldest = p!.at;
        final probs = ConnectionAlerts.detect(p.snap!, t);
        (probs.isEmpty ? healthy : rows)
            .add(SubsCheckRow(s, [for (final q in probs) (kind: q.kind, label: q.label)], reading: local));
        continue;
      }
      final note = companyNote?.call(s.companyKey);
      missing.add((
        sub: s,
        why: v != null
            ? SubsMissWhy.dead
            : note != null
                ? SubsMissWhy.company
                : p?.snap != null
                    ? SubsMissWhy.noMetrics
                    : (s.isOnline ? SubsMissWhy.noReply : SubsMissWhy.offline),
        note: note,
      ));
    }
    return _report(subs.length, rows, healthy, missing, limits, oldest: oldest);
  }

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
