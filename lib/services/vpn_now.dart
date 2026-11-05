import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/vpn_now_api.dart';
import 'agent_net_presence.dart';
import 'device_warm_service.dart';

export '../api/vpn_now_api.dart' show VpnNowKind, VpnSubReading, VpnDeviceResult, VpnNowResult;

enum VpnBarPhase { idle, running, done, failed }

/// فحصٌ واحد عبر الـVPN (المشتركون أو الأجهزة) — الشريط يرسمه: يتّصل ⇒ «يفحص… ١٢٠ من ٣١٠» ⇒ النتيجة أو السبب.
/// الضغطة والفحص جارٍ لا تبدأ ثانياً (والخادم نفسه يعيد الفحص نفسه خلال دقيقتين).
class VpnNowJob extends ChangeNotifier {
  VpnNowJob(this.kind);
  final VpnNowKind kind;

  VpnBarPhase phase = VpnBarPhase.idle;
  String? line;
  String? sub;

  /// التقدّم ٠..١ — null = غير محدّد (يتّصل/يقرأ السكترات).
  double? value;
  VpnNowResult? result;

  /// سبب الفشل من الخادم (tunnel_failed، no_vpn…) — يقرّر زرّ «صفحة VPN».
  String? reason;

  /// بدء آخر فحص — «وضع VPN» يعيده بعد [VpnNow.intervalOf].
  DateTime? startedAt;
  int _gen = 0;

  bool get busy => phase == VpnBarPhase.running;
  String get _what => kind == VpnNowKind.devices ? 'أجهزتك' : 'مشتركينك';

  Future<void> run() async {
    if (busy) return;
    final gen = ++_gen;
    startedAt = VpnNow.now();
    phase = VpnBarPhase.running;
    line = 'يتّصل بالـVPN…';
    sub = 'تقدر تطلع من الشاشة — الفحص يكمل';
    value = null;
    result = null;
    reason = null;
    notifyListeners();
    final st = await VpnNowApi.start(kind);
    if (gen != _gen) return;
    final id = st.id;
    if (id == null) {
      _fail(st.error ?? 'تعذّر الفحص الآن — حاول بعد قليل');
      return;
    }
    final started = DateTime.now();
    var misses = 0;
    while (gen == _gen) {
      await Future<void>.delayed(VpnNow.pollEvery);
      if (gen != _gen) return;
      final p = await VpnNowApi.poll(id);
      if (gen != _gen) return;
      if (p == null) {
        if (++misses >= 6) {
          _fail('انقطع الاتّصال بالخادم — أعد المحاولة');
          return;
        }
        continue;
      }
      misses = 0;
      if (p.done) {
        _finish(p.result ?? const VpnNowResult(ok: false, message: 'تعذّر الفحص الآن — حاول بعد قليل'));
        return;
      }
      _progress(p.progress);
      if (DateTime.now().difference(started) > VpnNow.maxWait) {
        _fail('الفحص أطول من المعتاد — أعد بعد قليل');
        return;
      }
    }
  }

  void _progress(VpnNowProgress? pr) {
    if (pr == null) return;
    switch (pr.phase) {
      case 'online':
        line = 'يجلب المتّصلين…';
        value = null;
      case 'sectors':
        line = 'يقرأ السكترات…';
        value = null;
      case 'olts':
        line = 'يقرأ الأولت…';
        value = null;
      case 'probing':
        if (pr.total > 0) {
          line = 'يفحص $_what… ${pr.done} من ${pr.total}';
          value = (pr.done / pr.total).clamp(0.0, 1.0);
        } else {
          line = 'يفحص $_what…';
          value = null;
        }
      case 'finishing':
        line = 'يجمع النتيجة…';
        value = 1;
      default:
        line = 'يتّصل بالـVPN…';
        value = null;
    }
    notifyListeners();
  }

  void _finish(VpnNowResult r) {
    result = r;
    if (!r.ok) {
      _fail(r.message, reason: r.reason);
      return;
    }
    VpnNow._apply(kind, r);
    phase = VpnBarPhase.done;
    line = r.message;
    sub = r.detail;
    value = null;
    notifyListeners();
  }

  void _fail(String msg, {String? reason}) {
    phase = VpnBarPhase.failed;
    line = msg;
    sub = null;
    value = null;
    this.reason = reason;
    notifyListeners();
  }

  /// يترك الفحص الجاري (الخادم يكمله وحده) ويرجع بلا نتيجة — إطفاء «وضع VPN».
  void cancel() {
    _gen++;
    phase = VpnBarPhase.idle;
    line = null;
    sub = null;
    value = null;
    result = null;
    reason = null;
    notifyListeners();
  }

  /// يُغلق النتيجة أو الخطأ (لا يوقف فحصاً جارياً بالخادم).
  void clear() {
    if (busy) return;
    phase = VpnBarPhase.idle;
    line = null;
    sub = null;
    result = null;
    reason = null;
    notifyListeners();
  }

  /// تبديل الحساب/الخروج: يُنسى كلّ شيء ويُترك أيّ استطلاعٍ جارٍ.
  void reset() {
    _gen++;
    startedAt = null;
    phase = VpnBarPhase.idle;
    line = null;
    sub = null;
    value = null;
    result = null;
    reason = null;
    notifyListeners();
  }
}

/// «فحص الآن» عبر VPN (٥ نوفمبر — المالك: «الوكيل… مو ضمن الشبكة… فحص الان بالمشتركين… وكذلك الاجهزة»): نتائج آخر فحص
/// (قراءة كلّ مشترك وحال كلّ جهاز، ٣٠ دقيقة) لكروت القائمة، وطريق الوكيل (مربوط أم لا)، وإخفاء الهنت لليوم.
class VpnNow {
  VpnNow._();

  @visibleForTesting
  static Duration pollEvery = const Duration(milliseconds: 2500);
  static Duration maxWait = const Duration(minutes: 6);
  static const ttl = Duration(minutes: 30);

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  // ── «وضع VPN» (٥ نوفمبر — المالك: «اريد من ينقر ع vpn يتفعل الفحص يتوجه ع vpn… لازم نخلي حارس فحص بداخل التطبيق يفحص
  //    متى يكون بنك ناصي… حتى يعرفه هو داخل شبكه يحول الفحص للشبكه بدون vpn») ──
  // زرّ VPN بالقسمين يشغّله: الفحص المباشر من الموبايل يتوقّف، والفحص عبر الـVPN يتكرّر للقسم الظاهر ([attach]) — الأجهزة كلّ
  // دقيقة والمشتركون كلّ ٣ د على نفق الشركة الدائم، وأبطأ على ملفّه/قالب شركته (غرفةٌ مؤقّتة أثقل). والحارس كلّ ٢٠ث يجرّب عناوين
  // شبكة الوكيل الخاصّة: أوّل ردٍّ ⇒ رجع لشبكته ⇒ الوضع ينطفي وحده والفحص يرجع مباشراً ([notice] «رجعت لشبكتك»).
  // دخله وهو على شبكته (ضغطةٌ صريحة) ⇒ الحارس لا يُطفئه حتى يرى الشبكة تغيب مرّةً ثمّ تعود.
  static final ValueNotifier<bool> mode = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> notice = ValueNotifier<String?>(null);
  static final Map<VpnNowKind, int> _attached = {};
  static Timer? _loop;
  static Timer? _noticeTimer;
  static DateTime? _guardAt;
  static bool _armed = false;
  static bool _guarding = false;
  static String? _via;

  @visibleForTesting
  static Duration loopEvery = const Duration(seconds: 10);
  @visibleForTesting
  static Duration guardEvery = const Duration(seconds: 20);

  /// الحارس في الاختبار: true على الشبكة · false خارجها · null لا يُعرف.
  @visibleForTesting
  static Future<bool?> Function()? guardProbe;

  /// مصادر إضافيّة للحارس (قسم الأجهزة: أجهزة الوكيل بعناوينها الخاصّة) — true/false/null كـ[guardProbe].
  static final Map<String, Future<bool?> Function()> guardSources = {};

  static bool get isOn => mode.value;

  /// كم بين فحصين بالوضع — نفق الشركة الدائم أخفّ من الغرفة المؤقّتة.
  static Duration intervalOf(VpnNowKind k) {
    final company = _via == 'company';
    if (k == VpnNowKind.devices) return Duration(seconds: company ? 60 : 180);
    return Duration(seconds: company ? 180 : 300);
  }

  /// يشغّل الوضع ويفحص [from] فوراً (والأقسام الظاهرة).
  static Future<void> enterMode({VpnNowKind? from}) async {
    if (mode.value) {
      if (from != null) unawaited(jobOf(from).run());
      return;
    }
    _noticeTimer?.cancel();
    notice.value = null;
    _armed = AgentNetPresence.current != NetPresence.on;
    _guardAt = now(); // لا حارس بالثواني الأولى — الضغطة نفسها قرار
    mode.value = true;
    _loop?.cancel();
    _loop = Timer.periodic(loopEvery, (_) => unawaited(_tick()));
    if (from != null) unawaited(jobOf(from).run());
    unawaited(route().then((r) => _via = r?.via));
    unawaited(_tick());
  }

  /// يطفئ الوضع: [auto] = الحارس رأى شبكة الوكيل ⇒ سطر «رجعت لشبكتك» لحظات. نتائج الوضع تُغلق (القراءات تبقى ٣٠ د).
  static void exitMode({bool auto = false}) {
    if (!mode.value) return;
    _loop?.cancel();
    _loop = null;
    mode.value = false;
    subscribers.cancel();
    devices.cancel();
    if (auto) {
      notice.value = 'رجعت لشبكتك — الفحص صار مباشر من موبايلك';
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 8), () {
        if (!mode.value) notice.value = null;
      });
    }
  }

  static void dismissNotice() {
    _noticeTimer?.cancel();
    notice.value = null;
  }

  /// القسم ظاهر (تبويبٌ نشط والتطبيق بالواجهة) ⇒ يُحدَّث بالوضع؛ [detach] حين يختفي.
  static void attach(VpnNowKind k) {
    _attached[k] = (_attached[k] ?? 0) + 1;
    if (mode.value) unawaited(_tick());
  }

  static void detach(VpnNowKind k) {
    final n = (_attached[k] ?? 0) - 1;
    if (n <= 0) {
      _attached.remove(k);
    } else {
      _attached[k] = n;
    }
  }

  @visibleForTesting
  static Set<VpnNowKind> get attached => _attached.keys.toSet();

  static bool get _foreground {
    final st = WidgetsBinding.instance.lifecycleState;
    return st == null || st == AppLifecycleState.resumed;
  }

  /// نبضة الوضع: الحارس (كلّ [guardEvery]) ثمّ فحص كلّ قسمٍ ظاهر حان موعده.
  @visibleForTesting
  static Future<void> tick() => _tick();

  static Future<void> _tick() async {
    if (!mode.value || !_foreground) return;
    final t = now();
    final g = _guardAt;
    if (!_guarding && (g == null || t.difference(g) >= guardEvery)) {
      _guardAt = t;
      _guarding = true;
      bool? on;
      try {
        on = await _guard();
      } catch (_) {
        on = null;
      } finally {
        _guarding = false;
      }
      if (!mode.value) return;
      if (on == false) _armed = true;
      if (on == true && _armed) {
        exitMode(auto: true);
        return;
      }
    }
    for (final k in _attached.keys.toList()) {
      final job = jobOf(k);
      if (job.busy) continue;
      final last = job.startedAt;
      if (last == null || now().difference(last) >= intervalOf(k)) unawaited(job.run());
    }
  }

  /// «هل رجع لشبكته؟» — مصادر الأقسام (أجهزته) ثمّ عيّنة المشتركين ([DeviceWarmService.onAgentNetwork]): ردٌّ واحد يكفي.
  static Future<bool?> _guard() async {
    final f = guardProbe;
    if (f != null) return f();
    bool? out;
    for (final src in guardSources.values.toList()) {
      final r = await src();
      if (r == true) return true;
      if (r == false) out = false;
    }
    final s = await DeviceWarmService.onAgentNetwork();
    if (s == true) return true;
    return s ?? out;
  }

  static final subscribers = VpnNowJob(VpnNowKind.subscribers);
  static final devices = VpnNowJob(VpnNowKind.devices);
  static VpnNowJob jobOf(VpnNowKind k) => k == VpnNowKind.devices ? devices : subscribers;

  /// يرتفع مع كلّ نتيجة — كروت القائمة تستمع له.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static final _readings = <String, VpnSubReading>{};
  static DateTime? _readAt;
  static final _devices = <int, VpnDeviceResult>{};
  static DateTime? _devAt;

  static bool _fresh(DateTime? at) => at != null && DateTime.now().difference(at) < ttl;

  /// قراءة مشتركٍ من آخر فحصٍ عبر الـVPN (≤ ٣٠ دقيقة) — null إن لم يُفحص.
  static VpnSubReading? readingFor(String username) {
    if (!_fresh(_readAt)) return null;
    return _readings[username.trim().toLowerCase()];
  }

  static VpnDeviceResult? deviceFor(int id) => _fresh(_devAt) ? _devices[id] : null;

  static void _apply(VpnNowKind k, VpnNowResult r) {
    if (k == VpnNowKind.devices) {
      _devices
        ..clear()
        ..addEntries(r.devices.map((d) => MapEntry(d.id, d)));
      _devAt = DateTime.now();
    } else {
      _readings
        ..clear()
        ..addAll(r.readings);
      _readAt = DateTime.now();
    }
    version.value++;
  }

  @visibleForTesting
  static void debugApply(VpnNowKind k, VpnNowResult r) => _apply(k, r);

  // ── طريق الوكيل (مربوط أم لا) — خمس دقائق ──
  static ({bool linked, String? via})? _route;
  static DateTime? _routeAt;
  static Future<({bool linked, String? via})?>? _routeP;

  @visibleForTesting
  static Future<({bool linked, String? via})?> Function() routeSource = VpnNowApi.route;

  static Future<({bool linked, String? via})?> route({bool force = false}) {
    final at = _routeAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(minutes: 5)) return Future.value(_route);
    return _routeP ??= routeSource().then((r) {
      _route = r;
      _routeAt = DateTime.now();
      return r;
    }).whenComplete(() => _routeP = null);
  }

  // ── إخفاء الهنت لباقي اليوم ──
  static final ValueNotifier<int> dismissals = ValueNotifier<int>(0);
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static String _key(VpnNowKind k) => 'vpnnow.dismiss.${k.wire}';

  static Future<bool> dismissedToday(VpnNowKind k) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_key(k)) == _today();
    } catch (_) {
      return false;
    }
  }

  static Future<void> dismiss(VpnNowKind k) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(k), _today());
    } catch (_) {/* الذاكرة تكفي للجلسة */}
    dismissals.value++;
  }

  /// يُعيد الهنت (من قائمة القسم: «فحص عبر VPN»).
  static Future<void> undismiss(VpnNowKind k) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key(k));
    } catch (_) {}
    dismissals.value++;
  }

  /// خروجٌ/تبديل حساب — `SessionManager.clearAllSessionData`.
  static void reset() {
    _loop?.cancel();
    _loop = null;
    _noticeTimer?.cancel();
    mode.value = false;
    notice.value = null;
    _armed = false;
    _guardAt = null;
    _via = null;
    _readings.clear();
    _devices.clear();
    _readAt = null;
    _devAt = null;
    _route = null;
    _routeAt = null;
    subscribers.reset();
    devices.reset();
    version.value++;
  }
}
