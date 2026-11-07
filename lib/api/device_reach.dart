import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';

import '../core/net/device_net.dart';
import '../models/network_device.dart';
import 'olt_profile.dart';

/// ما ردّ به منفذ TCP: اتّصل · رُفض (RST) · صمت (مهلة/لا طريق).
enum PortReply { open, refused, silent }

/// ردّ منفذٍ واحد وزمنه (ms) — `ms` للاتّصال والرفض وحدهما.
typedef PortAnswer = ({int port, PortReply reply, int? ms});

/// منفذٌ أثبت أنّ الجهاز يردّ، وزمنه.
typedef ReachHit = ({int port, int? ms, PortReply reply});

/// نتيجة ping (ICMP) أو فحص خدمة — كـ`Probe3` في `network_devices_api.dart` (نوعٌ بنيويّ واحد).
typedef ReachProbe = ({String status, int? responseMs, double? packetLoss});

/// كيف ثبت أنّ الجهاز يردّ.
enum ReachVia {
  /// ping حقيقيّ (ICMP).
  ping,

  /// خدمة الإدارة المسجّلة (المنفذ والبروتوكول المحفوظان).
  service,

  /// منفذ إدارةٍ شائعٌ غير المسجّل (TCP) — حيث لا ping (iOS) أو حجبه الجهاز.
  port,
}

/// نتيجة «فحص الآن (ping)» وفحص ما بعد الحفظ: **هل يردّ الجهاز على الشبكة** — مستقلّاً عن علامته وبياناته ومنفذه المسجّلة —
/// وهل ردّت خدمة إدارته.
///
/// المالك (١ نوفمبر): «اذا الجهاز حتى لو ما مضيوف صح المفروض تخلي زر فحص الجهاز بالبنك يرد ويظهر شعار الجهاز يرد بنك
/// اتصال ping تاكد من الاعدادات الجهاز».
@immutable
class DeviceCheck {
  const DeviceCheck({
    required this.reachable,
    this.latencyMs,
    this.packetLoss,
    this.serviceOk,
    this.via,
    this.port,
    this.icmpTried = false,
  });

  /// يردّ على الشبكة (ping أو خدمته أو منفذٌ شائع).
  final bool reachable;

  /// زمن الردّ: متوسّط الـping إن ردّ، وإلّا زمن أوّل اتّصال.
  final int? latencyMs;

  /// فقدان الحزم — من الـping وحده. `null` = لا ping (iOS، أو حجبه الجهاز والجهاز يردّ بغيره): لا «100%» مع «يردّ».
  final double? packetLoss;

  /// ردّت خدمة الإدارة المسجّلة (المنفذ/البروتوكول/الـcommunity)؟ false مع [reachable] = الإعدادات خطأ لا الجهاز مفصول.
  final bool? serviceOk;
  final ReachVia? via;

  /// المنفذ الذي ردّ حين [via] = [ReachVia.port].
  final int? port;

  /// جُرّب الـping فعلاً (أندرويد/الماك/ويندوز) — لصياغة «لا يردّ على ping» بصدق.
  final bool icmpTried;

  String get status => reachable ? 'online' : 'offline';

  @override
  String toString() =>
      'DeviceCheck(reachable: $reachable, ms: $latencyMs, loss: $packetLoss, serviceOk: $serviceOk, via: $via, port: $port, icmp: $icmpTried)';
}

/// فحص الوصول المستقلّ عن سجلّ الجهاز: منافذ الإدارة الشائعة لعلامته والعامّة معاً، بمهلٍ قصيرة وبالتوازي.
///
/// ── لماذا لا يكفي منفذ السجلّ ──────────────────────────────────────
/// الجهاز المسجّل بمنفذٍ/علامةٍ/بياناتٍ خطأ لا تردّ خدمته، فكان يُعرض «مفصولاً» وهو يعمل — وعلى iOS بلا ping أصلاً (dart_ping لا
/// يُعتمد عليه هناك) لم يكن من سبيلٍ آخر. هنا يُسأل الجهاز على منافذ إدارته المعروفة: أوّل منفذٍ يردّ يُثبت الوصول وزمنه.
///
/// ── ما لا يُصدَّق وحده ─────────────────────────────────────────────
/// • **منافذ الويب** ([webPorts]): وسيط الموبايل الشفّاف يقبل أيّ عنوانٍ على :80 (قيس من الماك على نقطة اتّصال الآيفون:
///   ‏192.0.2.1:80 «اتّصل» بـ23ms). • **الرفض (RST)**: قد يردّه جدارٌ بالطريق عن أيّ عنوان. كلاهما يُصدَّق بعد سؤال [canaryHost]
///   — عنوانٌ لا جهاز عليه — على المنفذ نفسه: إن سكت فالردّ من الجهاز، وإن ردّ فالشبكة تختلقه ولا يُحسب.
///
/// ── ما لا يُطرق كثيراً ─────────────────────────────────────────────
/// منافذ الدخول ([guarded]: SSH · Telnet · FTP · Winbox) تحميها قواعد «حماية التخمين» الشائعة في ميكروتك (اتّصالاتٌ جديدة خلال
/// دقائق ⇒ حظر عنوان المدير): لا تُطرق إلّا إن لم يردّ غيرها، وفي الفحص بالطلب وحده، ومرّةً كلّ [guardedEvery] للعنوان — ولا
/// تدخل الجولة الدوريّة أبداً.
class DeviceReach {
  DeviceReach._();

  /// مهلة كلّ منفذ — قصيرة: على الشبكة المحلّيّة يردّ الجهاز بأجزاءٍ من الثانية.
  static const timeout = Duration(milliseconds: 1500);

  /// منافذ الويب — يقبلها وسيط الموبايل عن أيّ عنوان.
  static const webPorts = {80, 443, 8080, 8443};

  /// منافذ الدخول المحميّة بقواعد حماية التخمين.
  static const guarded = {21, 22, 23, 8291};

  /// المنافذ الشائعة لكلّ علامة (الأكثر احتمالاً أوّلاً).
  static const brandPorts = <String, List<int>>{
    'mikrotik': [8728, 8291, 8729, 80, 443, 22, 23],
    'ubnt': [443, 80, 22, 8080],
    'mimosa': [443, 80, 22],
    'cisco': [22, 23, 443, 80],
    'ruijie': [443, 80, 22, 23],
  };

  /// الأولتيات (VSOL · BDCOM · HSGQ · C-Data): واجهة الويب وTelnet.
  static const oltPorts = [80, 23, 443, 22, 8080];

  /// العامّة — الجهاز قد يكون مسجّلاً بعلامةٍ غير علامته (أولتٌ سُجّل ميكروتك).
  static const genericPorts = [80, 443, 22, 23, 8291, 8728, 8080];

  /// عنوانٌ لا جهاز عليه (TEST-NET-1، RFC 5737) — «الشاهد».
  static String canaryHost = '192.0.2.1';

  /// كم يُحفظ حكم الشاهد لكلّ منفذ — نافذةٌ قصيرة: الهاتف ينتقل بين الواي فاي وبيانات الجوّال.
  static const canaryFor = Duration(seconds: 30);

  /// منافذ الدخول المحميّة: مرّةً كلّ هذه المدّة للعنوان على الأكثر. القاعدة الكلاسيكيّة في ميكروتك تحظر بعد أربعة اتّصالاتٍ جديدة
  /// كلٌّ منها خلال دقيقةٍ من سابقه — فطرقةٌ كلّ دقيقتين (مع طرقة `mikrotikProbe` كلّ ٥ دقائق) لا تتجاوز المرحلة الثانية أبداً.
  /// وما ثبت بها يُعاد داخل النافذة: فحصان متتاليان لا يقولان قولين.
  static const guardedEvery = Duration(minutes: 2);

  /// اتّصال TCP واحد.
  static Future<PortAnswer> connect(String host, int port, Duration timeout) => (debugConnect ?? _connect)(host, port, timeout);

  /// الاختبار: ردودٌ مزيّفة بدل الشبكة.
  @visibleForTesting
  static Future<PortAnswer> Function(String host, int port, Duration timeout)? debugConnect;

  /// الساعة — للاختبار.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  static final Map<int, ({DateTime at, Future<PortReply> verdict})> _canary = {};
  static final Map<String, ({DateTime at, ReachHit? hit})> _guardedAt = {};

  @visibleForTesting
  static void resetForTest() {
    _canary.clear();
    _guardedAt.clear();
    debugConnect = null;
    now = DateTime.now;
    canaryHost = '192.0.2.1';
  }

  /// رفضُ الاتّصال (RST): 61 ماك/iOS · 111 أندرويد/لينكس · 10061 ويندوز.
  static bool isRefused(Object e) {
    if (e is! SocketException) return false;
    final code = e.osError?.errorCode;
    return code == 61 || code == 111 || code == 10061 || '${e.osError?.message} ${e.message}'.toLowerCase().contains('refused');
  }

  static Future<PortAnswer> _connect(String host, int port, Duration timeout) async {
    final sw = Stopwatch()..start();
    try {
      // «وضع VPN» (٧ نوفمبر): الاتّصال عبر الممرّ وزمنه من داخل النفق (كأنّه على شبكة الوكيل)
      final s = await DeviceNet.connect(host, port, timeout: timeout);
      final ms = DeviceNet.connectMs(s) ?? sw.elapsedMilliseconds;
      s.destroy();
      return (port: port, reply: PortReply.open, ms: ms);
    } catch (e) {
      if (isRefused(e)) return (port: port, reply: PortReply.refused, ms: sw.elapsedMilliseconds);
      return (port: port, reply: PortReply.silent, ms: null);
    }
  }

  /// أولتٌ بالعلامة أو بالطراز (سجلّاتٌ قديمة `other`/`vsol`).
  static bool _isOlt(NetworkDevice d) =>
      const {'vsol', 'bdcom', 'hsgq', 'cdata'}.contains(d.brand.toLowerCase()) || OltProfile.fromDevice(d).vendor != OltVendor.unknown;

  /// منافذ الفحص لهذا الجهاز: منافذ علامته ثمّ العامّة، بلا تكرار وبلا منفذ خدمته ([exclude]: يُفحص وحده).
  /// [periodic] (جولة القائمة كلّ ٢٠ث): بلا منافذ الدخول المحميّة ([guarded]).
  static List<int> portsFor(NetworkDevice d, {bool periodic = false, Set<int> exclude = const {}}) {
    final b = d.brand.toLowerCase();
    final own = brandPorts[b] ?? (_isOlt(d) ? oltPorts : const <int>[]);
    return <int>{...own, ...genericPorts}.where((p) => !exclude.contains(p) && !(periodic && guarded.contains(p))).toList();
  }

  /// يحتاج هذا الردّ شهادة [canaryHost]؟ اتّصالٌ على منفذ ويب، أو رفض.
  static bool needsCanary(int port, PortReply reply) => reply == PortReply.refused || (reply == PortReply.open && webPorts.contains(port));

  /// هل يُثبت هذا الردّ أنّ **الجهاز** يردّ؟ [canary] = ردّ الشاهد على المنفذ نفسه (null = لم يُسأل).
  static bool counts(int port, PortReply reply, PortReply? canary) {
    if (reply == PortReply.silent) return false;
    if (!needsCanary(port, reply)) return true;
    return canary == PortReply.silent;
  }

  /// ردّ الشاهد على [port] — محفوظٌ [canaryFor]، والسؤال الجاري يُشارَك (جولةٌ من ثمانين جهازاً = سؤالٌ واحد).
  static Future<PortReply> canary(int port) {
    final c = _canary[port];
    final t = now();
    if (c != null && t.difference(c.at) < canaryFor) return c.verdict;
    final f = Future.sync(() => connect(canaryHost, port, timeout)).then((a) => a.reply, onError: (Object _) => PortReply.silent);
    _canary[port] = (at: t, verdict: f);
    return f;
  }

  /// يصدّق ردّاً على منفذ خدمةٍ مسجّل (ويب) — اتّصالٌ على :80 عبر وسيط الموبايل ليس ردّاً من الجهاز.
  /// [ip] عبر ممرّ «وضع VPN» ⇒ الردّ من داخل النفق (لا وسيط موبايلٍ بالطريق) فلا شاهد.
  static Future<bool> trusts(int port, PortReply reply, {String? ip}) async {
    if (reply == PortReply.silent) return false;
    if (!needsCanary(port, reply)) return true;
    if (ip != null && DeviceNet.viaPipe(ip)) return true;
    return counts(port, reply, await canary(port));
  }

  /// يسأل [ip] على [ports]: أوّل ردٍّ مُصدَّق يُعاد فوراً (لا ينتظر أبطأها)، و`null` إن لم يردّ شيء.
  ///
  /// منافذ الدخول المحميّة ([guarded]) لا تُطرق إلّا إن لم يردّ غيرها، وفي الفحص بالطلب وحده ([allowGuarded])، ومرّةً كلّ
  /// [guardedEvery] للعنوان — وما ثبت بها يُعاد داخل النافذة.
  static Future<ReachHit?> sweep(String ip, List<int> ports, {bool allowGuarded = false}) async {
    if (ip.trim().isEmpty) return null;
    final all = ports.toSet();
    final hit = await _race(ip, all.where((p) => !guarded.contains(p)).toList());
    if (hit != null || !allowGuarded) return hit;
    final knock = all.where(guarded.contains).toList();
    if (knock.isEmpty) return null;
    final t = now();
    final prev = _guardedAt[ip];
    if (prev != null && t.difference(prev.at) < guardedEvery) return prev.hit;
    if (_guardedAt.length > 500) _guardedAt.remove(_guardedAt.keys.first);
    _guardedAt[ip] = (at: t, hit: null); // الطرقة تُسجَّل قبل وقوعها — فحصٌ موازٍ لا يطرق ثانيةً.
    final g = await _race(ip, knock);
    _guardedAt[ip] = (at: t, hit: g);
    return g;
  }

  /// المنافذ معاً — أوّل ردٍّ مُصدَّق يفوز.
  static Future<ReachHit?> _race(String ip, List<int> ports) {
    if (ports.isEmpty) return Future.value(null);
    final done = Completer<ReachHit?>();
    var left = ports.length;
    void settle() {
      left -= 1;
      if (left == 0 && !done.isCompleted) done.complete(null);
    }

    // عبر ممرّ «وضع VPN»: الردّ من داخل النفق — لا وسيط موبايلٍ يختلقه، فلا شاهد
    final piped = DeviceNet.viaPipe(ip);
    for (final p in ports) {
      Future.sync(() => connect(ip, p, timeout)).then((a) async {
        try {
          if (done.isCompleted) return;
          if (a.reply == PortReply.silent) return settle();
          if (piped || !needsCanary(p, a.reply)) return done.complete((port: p, ms: a.ms, reply: a.reply));
          final c = await canary(p);
          if (done.isCompleted) return;
          if (counts(p, a.reply, c)) return done.complete((port: p, ms: a.ms, reply: a.reply));
          settle();
        } catch (_) {
          // لا يعلق الفحص على منفذٍ واحد.
          if (!done.isCompleted) settle();
        }
      }, onError: (Object _) => settle());
    }
    return done.future;
  }

  /// الحكم — دالّةٌ خالصة (الاختبارات تسقيها نتائج مزيّفة):
  /// ① ردّ الـping ⇒ يردّ، بزمنه وفقدانه؛ ② وإلّا الخدمة المسجّلة ⇒ يردّ بزمنها بلا «فقدان» (الـping محجوبٌ أو لا ping)؛
  /// ③ وإلّا منفذٌ شائع ⇒ يردّ والخدمة لا (الإعدادات)؛ ④ وإلّا لا يردّ — والفقدان 100% فقط إن أُرسل ping فعلاً.
  static DeviceCheck decide({ReachProbe? icmp, required ReachProbe service, ReachHit? hit}) {
    final svcOk = service.status == 'online';
    final tried = icmp != null;
    if (icmp != null && icmp.status == 'online') {
      return DeviceCheck(
          reachable: true, latencyMs: icmp.responseMs, packetLoss: icmp.packetLoss, serviceOk: svcOk, via: ReachVia.ping, icmpTried: true);
    }
    if (svcOk) {
      return DeviceCheck(reachable: true, latencyMs: service.responseMs, serviceOk: true, via: ReachVia.service, icmpTried: tried);
    }
    if (hit != null) {
      return DeviceCheck(reachable: true, latencyMs: hit.ms, serviceOk: false, via: ReachVia.port, port: hit.port, icmpTried: tried);
    }
    return DeviceCheck(reachable: false, packetLoss: tried ? 100.0 : null, serviceOk: false, icmpTried: tried);
  }
}
