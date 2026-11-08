import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/company_route.dart';
import '../api/vpn_now_api.dart';
import '../core/net/vpn_pipe.dart';
import 'agent_net_presence.dart';
import 'connection_alerts.dart';
import 'device_warm_service.dart';
import 'merged_text.dart';

export '../api/vpn_now_api.dart' show VpnNowKind, VpnSubReading, VpnDeviceResult, VpnNowResult;

enum VpnBarPhase { idle, running, done, failed }

/// «كل الشركات»: شركةٌ في نطاق فحص المشتركين عبر الـVPN (مفتاحها واسمها).
typedef VpnMergedCompany = ({String key, String name});

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

  bool get busy => phase == VpnBarPhase.running || _checking;

  /// «كل الشركات»: شركات الفحص الجاري بترتيبها، والتي تُفحص الآن — لبطاقة «الشركات» في «الفحص العامّ» (بانتظار دورها/تُفحص).
  List<String> queue = const [];
  String? current;

  /// تأكّد الطريق جارٍ (الأجهزة) — والشريط على حاله («متّصل» لا دائرة كلّ دقيقة).
  bool _checking = false;
  String get _what => kind == VpnNowKind.devices ? 'أجهزتك' : 'مشتركينك';

  /// [only] («كل الشركات»): هذه الشركات وحدها — «الفحص العامّ» يقرأ المفتوحة من شبكتك ويفحص غيرها عبر VPN شركتها.
  Future<void> run({List<VpnMergedCompany>? only}) async {
    if (busy) return;
    if (kind == VpnNowKind.devices) return _runRoute();
    if (only != null && only.isEmpty) return;
    final merged = only ?? VpnNow._mergedNow;
    if (merged != null) return _runMerged(merged);
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

  /// «كل الشركات» (٧ نوفمبر — المالك: «فحص المشتركين… في كل الشركات… تنبيه الوكيل باسم الشركة إذا احتاج فحصها إلى VPN ولم يتوفر
  /// طريق لها»): شركات النطاق واحدةً بعد واحدة، كلٌّ بطلبٍ موجَّه بمفتاحها (بدء الفحص ونتيجته وحدود تنبيهها)، وقراءات كلّ شركةٍ في
  /// مكانها لا تختلط (اليوزر نفسه قد يكون في شركتين). الشريط نفسه: «يفحص مشتركي «الشركة»…» ثمّ النتيجة؛ ومن لم تُفحص تُسمّى بسببها.
  Future<void> _runMerged(List<VpnMergedCompany> scope) async {
    final gen = ++_gen;
    startedAt = VpnNow.now();
    phase = VpnBarPhase.running;
    line = 'يتّصل بالـVPN…';
    sub = 'تقدر تطلع من الشاشة — الفحص يكمل';
    value = null;
    result = null;
    reason = null;
    notifyListeners();
    var ok = 0;
    var bad = 0;
    var badKnown = false;
    final notes = <String>[];
    queue = [for (final c in scope) c.key];
    for (var i = 0; i < scope.length; i++) {
      final c = scope[i];
      if (gen != _gen) return;
      final head = scope.length == 1 ? 'يفحص مشتركي «${c.name}»' : 'يفحص مشتركي «${c.name}» (${i + 1} من ${scope.length})';
      line = '$head…';
      value = null;
      current = c.key;
      notifyListeners();
      final r = await CompanyRoute.run(c.key, () => _sweepCompany(head, gen));
      if (gen != _gen) return;
      if (r.ok) {
        VpnNow._applyCompany(c.key, r);
        VpnNow._companyNotes.remove(c.key);
        ok++;
        if (r.problems != null) {
          badKnown = true;
          bad += r.problems!;
        }
        // حدود تنبيهها لورقة «المشاكل» (بحدود كلّ شركة) — تعذّرت ⇒ حدود المفتوحة
        if ((r.problems ?? 0) > 0) {
          final t = await CompanyRoute.run(c.key, VpnNow._companyLimitsFetch);
          if (gen != _gen) return;
          if (t != null) VpnNow._companyLimits[c.key] = t;
        }
      } else {
        VpnNow._dropCompany(c.key);
        final why = VpnNow.mergedReason(c, r);
        VpnNow._companyNotes[c.key] = why;
        notes.add(why);
      }
    }
    if (gen != _gen) return;
    current = null;
    queue = const [];
    if (ok == 0) {
      _fail(notes.isEmpty ? 'تعذّر الفحص الآن — حاول بعد قليل' : notes.join(' · '));
      return;
    }
    phase = VpnBarPhase.done;
    line = ok == scope.length
        ? (scope.length == 1 ? 'فُحص مشتركو «${scope.first.name}» عبر VPN ✓' : 'فُحصت ${scope.length} ${mergedWord('شركات', 'صفحات')} عبر VPN ✓')
        : 'فُحصت $ok من ${scope.length} ${mergedWord('شركات', 'صفحات')} عبر VPN';
    sub = [if (badKnown) (bad > 0 ? '$bad بمشكلة' : 'لا مشاكل'), ...notes].join(' · ');
    value = null;
    notifyListeners();
    VpnNow._doneInMode(kind);
  }

  /// فحصٌ واحد لشركة النطاق الحاليّ (موجَّه) ⇒ نتيجته؛ لا يرمي. التقدّم على الشريط باسمها.
  Future<VpnNowResult> _sweepCompany(String head, int gen) async {
    final st = await VpnNowApi.start(kind);
    if (gen != _gen) return const VpnNowResult(ok: false, message: 'أُلغي الفحص');
    final id = st.id;
    if (id == null) return VpnNowResult(ok: false, message: st.error ?? 'تعذّر الفحص الآن — حاول بعد قليل');
    final started = DateTime.now();
    var misses = 0;
    while (gen == _gen) {
      await Future<void>.delayed(VpnNow.pollEvery);
      if (gen != _gen) break;
      final p = await VpnNowApi.poll(id);
      if (gen != _gen) break;
      if (p == null) {
        if (++misses >= 6) return const VpnNowResult(ok: false, message: 'انقطع الاتّصال بالخادم — أعد المحاولة');
        continue;
      }
      misses = 0;
      if (p.done) return p.result ?? const VpnNowResult(ok: false, message: 'تعذّر الفحص الآن — حاول بعد قليل');
      final pr = p.progress;
      if (pr != null && pr.phase == 'probing' && pr.total > 0) {
        line = '$head… ${pr.done} من ${pr.total}';
        value = (pr.done / pr.total).clamp(0.0, 1.0);
        notifyListeners();
      }
      if (DateTime.now().difference(started) > VpnNow.maxWait) {
        return const VpnNowResult(ok: false, message: 'الفحص أطول من المعتاد — أعد بعد قليل');
      }
    }
    return const VpnNowResult(ok: false, message: 'أُلغي الفحص');
  }

  /// «وضع VPN» بقسم الأجهزة (٧ نوفمبر — المالك: «كانما الوكيل يفعل vpn خارجي»): لا فحص من الخادم — قرّاء القسم نفسها (الحال
  /// والبنك والقراءات والتحديث) تمرّ عبر الـVPN ([DeviceNet])؛ هنا يُتأكّد أنّ طريقه قائم (ويبقى ملفّه/قالبه متّصلاً) ويُقال له.
  Future<void> _runRoute() async {
    final gen = ++_gen;
    startedAt = VpnNow.now();
    _checking = true;
    try {
      await _routeOnce(gen);
    } finally {
      if (gen == _gen) _checking = false;
    }
  }

  Future<void> _routeOnce(int gen) async {
    if (phase != VpnBarPhase.done) {
      phase = VpnBarPhase.running;
      line = 'يتّصل بالـVPN…';
      sub = 'أجهزتك كأنّك على شبكتك';
      value = null;
      result = null;
      reason = null;
      notifyListeners();
    }
    final r = await VpnNow.pipeRoute();
    if (gen != _gen) return;
    if (!r.ok) {
      _fail(r.message ?? 'الـVPN ما اتّصل الآن — حاول بعد قليل', reason: r.reason);
      return;
    }
    final again = phase == VpnBarPhase.done;
    phase = VpnBarPhase.done;
    line = 'متّصل عبر الـVPN ✓';
    sub = 'أجهزتك تُقرأ وتتحدّث عبره — كأنّك على شبكتك';
    value = null;
    reason = null;
    notifyListeners();
    if (!again) VpnNow._doneInMode(kind);
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
    VpnNow._doneInMode(kind);
  }

  void _fail(String msg, {String? reason}) {
    phase = VpnBarPhase.failed;
    line = msg;
    sub = null;
    value = null;
    this.reason = reason;
    notifyListeners();
    // الفشل يحتاج عيناً — يظهر الشريط وإن أُخفي
    VpnNow._showBar(kind);
  }

  /// يترك الفحص الجاري (الخادم يكمله وحده) ويرجع بلا نتيجة — إطفاء «وضع VPN».
  void cancel() {
    _gen++;
    _checking = false;
    queue = const [];
    current = null;
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
    _checking = false;
    queue = const [];
    current = null;
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

  /// كم بين فحصين بالوضع — نفق الشركة الدائم أخفّ من الغرفة المؤقّتة. الأجهزة: تأكّد الطريق كلّ دقيقة (قرّاؤها تتحدّث بإيقاعها هي).
  static Duration intervalOf(VpnNowKind k) {
    final company = _via == 'company';
    if (k == VpnNowKind.devices) return const Duration(seconds: 60);
    return Duration(seconds: company ? 180 : 300);
  }

  /// طريق الوكيل عبر الـVPN الآن (ممرّ الأجهزة: الشريط والفحص الشامل) — يُستبدل في الاختبار.
  static Future<PipeRoute> Function() pipeRoute = VpnPipe.route;

  // ── الشريط بالوضع لا يبقى ظاهراً (٧ نوفمبر — المالك: «تنبيه متصل على ال vpn امكانيه خفاء مايبقى ظاهر ع طول… بصفحه المشتركين
  //    وصحفه الاجهزه»): بعد نجاح الاتّصال يختفي وحده بعد ثوانٍ، و[×] يخفيه الآن؛ الفشل يُظهره؛ والوضع يبقى (درعه ممتلئ بالأدوات). ──
  static final ValueNotifier<Set<VpnNowKind>> hidden = ValueNotifier<Set<VpnNowKind>>(<VpnNowKind>{});
  static final Map<VpnNowKind, Timer> _hideTimers = {};
  @visibleForTesting
  static Duration autoHideAfter = const Duration(seconds: 6);

  static bool isHidden(VpnNowKind k) => hidden.value.contains(k);

  static void hideBar(VpnNowKind k) {
    _hideTimers.remove(k)?.cancel();
    if (!hidden.value.contains(k)) hidden.value = {...hidden.value, k};
  }

  static void _showBar(VpnNowKind k) {
    _hideTimers.remove(k)?.cancel();
    if (hidden.value.contains(k)) hidden.value = {...hidden.value}..remove(k);
  }

  static void _doneInMode(VpnNowKind k) {
    if (!mode.value || hidden.value.contains(k)) return;
    _hideTimers.remove(k)?.cancel();
    _hideTimers[k] = Timer(autoHideAfter, () {
      _hideTimers.remove(k);
      if (mode.value) hideBar(k);
    });
  }

  static void _resetBars() {
    for (final t in _hideTimers.values) {
      t.cancel();
    }
    _hideTimers.clear();
    if (hidden.value.isNotEmpty) hidden.value = <VpnNowKind>{};
  }

  /// يشغّل الوضع ويفحص [from] فوراً (والأقسام الظاهرة).
  static Future<void> enterMode({VpnNowKind? from}) async {
    // مشتركو الوطنيّ/فايبر اكس لا يُفحصون عبر الـVPN ⇒ الضغطة من قسمهم تشغّل الوضع بلا فحصٍ لهم (الأجهزة وحدها)
    final runFrom = from != null && (from != VpnNowKind.subscribers || subscribersOk) ? from : null;
    if (mode.value) {
      if (runFrom != null) unawaited(jobOf(runFrom).run());
      return;
    }
    _noticeTimer?.cancel();
    notice.value = null;
    _resetBars();
    _armed = AgentNetPresence.current != NetPresence.on;
    _guardAt = now(); // لا حارس بالثواني الأولى — الضغطة نفسها قرار
    mode.value = true;
    _loop?.cancel();
    _loop = Timer.periodic(loopEvery, (_) => unawaited(_tick()));
    if (runFrom != null) unawaited(jobOf(runFrom).run());
    unawaited(route().then((r) => _via = r?.via));
    unawaited(_tick());
  }

  /// يطفئ الوضع: [auto] = الحارس رأى شبكة الوكيل ⇒ سطر «رجعت لشبكتك» لحظات. نتائج الوضع تُغلق (القراءات تبقى ٣٠ د).
  static void exitMode({bool auto = false}) {
    if (!mode.value) return;
    _loop?.cancel();
    _loop = null;
    mode.value = false;
    _resetBars();
    subscribers.cancel();
    devices.cancel();
    // ممرّ التطبيق (٧ نوفمبر): اتّصالاته وغرفة نفقه الباقية (ملفّه/قالب شركته) تُغلق الآن لا بعد خمولها
    if (VpnPipe.used) VpnPipe.release();
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
      // مشتركو الوطنيّ/فايبر اكس على شبكة الشركة ⇒ لا فحص لهم عبر الـVPN (الأجهزة تُفحص)
      if (k == VpnNowKind.subscribers && !subscribersOk) continue;
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

  // ── «كل الشركات» (٧ نوفمبر): فحص المشتركين لكلّ شركةٍ في نطاق القسم، وقراءاتها في مكانها ──

  /// نطاق الفحص الآن — يضبطه قسم المشتركين (الكلّ أو المختارة)؛ null أو فارغ ⇒ الشركة المفتوحة كما كان.
  static List<VpnMergedCompany>? Function()? mergedScope;

  static List<VpnMergedCompany>? get _mergedNow {
    final s = mergedScope?.call();
    return s == null || s.isEmpty ? null : s;
  }

  static final _companyReadings = <String, Map<String, VpnSubReading>>{};
  static final _companyReadAt = <String, DateTime>{};
  static final _companyLimits = <String, ConnectionAlertThresholds>{};

  static void _applyCompany(String company, VpnNowResult r) {
    _companyReadings[company] = Map.of(r.readings);
    _companyReadAt[company] = DateTime.now();
    _companyLimits.remove(company);
    version.value++;
  }

  /// فحصٌ لم ينجح لشركة ⇒ تُسقط قراءاتها السابقة (لا تبدو حديثة).
  static void _dropCompany(String company) {
    final hadReadings = _companyReadings.remove(company) != null;
    final hadAt = _companyReadAt.remove(company) != null;
    _companyLimits.remove(company);
    if (hadReadings || hadAt) version.value++;
  }

  static void clearCompanyReadings() {
    _companyNotes.clear();
    if (_companyReadings.isEmpty && _companyReadAt.isEmpty) return;
    _companyReadings.clear();
    _companyReadAt.clear();
    _companyLimits.clear();
    version.value++;
  }

  /// «كل الشركات»: لماذا لم تُفحص شركةٌ عبر الـVPN في آخر فحص (««ايرث لنك» تحتاج VPN»…) — null إن نجحت أو لم تُفحص.
  static final _companyNotes = <String, String>{};
  static String? noteOf(String company) => _companyNotes[company];

  @visibleForTesting
  static void debugNote(String company, String? note) =>
      note == null ? _companyNotes.remove(company) : _companyNotes[company] = note;

  @visibleForTesting
  static void debugApplyCompany(String company, VpnNowResult r) => _applyCompany(company, r);

  /// قراءات كلّ شركةٍ الحديثة (٣٠ د): المفتاح ⇒ (اليوزر صغيراً ⇒ قراءته).
  static Map<String, Map<String, VpnSubReading>> get companyReadings => {
        for (final e in _companyReadings.entries)
          if (_fresh(_companyReadAt[e.key])) e.key: Map.unmodifiable(e.value),
      };

  /// حدود تنبيه شركةٍ كما قُرئت بفحصها (null: لم تُقرأ ⇒ حدود المفتوحة).
  static ConnectionAlertThresholds? limitsOf(String company) => _companyLimits[company];

  /// حدود تنبيه الشركة داخل نطاقها الموجَّه — بلا مخبأ المفتوحة؛ null إن تعذّرت.
  static Future<ConnectionAlertThresholds?> _companyLimitsFetch() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/settings');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) return ConnectionAlertThresholds.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {}
    return null;
  }

  /// لماذا لم تُفحص شركة — باسمها (لا «حسابك»: الرسالة تخصّ شركةً من شركاتك).
  static String mergedReason(VpnMergedCompany c, VpnNowResult r) => switch (r.reason) {
        'no_vpn' => '«${c.name}» تحتاج VPN',
        'na' => '«${c.name}»: مشتركوها على شبكة الشركة',
        'tunnel_failed' => '«${c.name}»: نفق الـVPN لم يتّصل',
        'off' || 'no_company' => '«${c.name}»: الفحص عبر VPN غير مفتوح لها',
        _ => '«${c.name}»: ${r.message}',
      };

  /// يرتفع مع كلّ نتيجة — كروت القائمة تستمع له.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static final _readings = <String, VpnSubReading>{};
  static DateTime? _readAt;
  static final _devices = <int, VpnDeviceResult>{};
  static DateTime? _devAt;

  static bool _fresh(DateTime? at) => at != null && DateTime.now().difference(at) < ttl;

  /// قراءة مشتركٍ من آخر فحصٍ عبر الـVPN (≤ ٣٠ دقيقة) — null إن لم يُفحص. [company] (صفّ «كل الشركات»): من فحص شركته وحدها —
  /// لا من فحص المفتوحة: اليوزر نفسه قد يكون في شركتين.
  static VpnSubReading? readingFor(String username, {String? company}) {
    if (company != null) {
      if (!_fresh(_companyReadAt[company])) return null;
      return _companyReadings[company]?[username.trim().toLowerCase()];
    }
    if (!_fresh(_readAt)) return null;
    return _readings[username.trim().toLowerCase()];
  }

  /// متى آخر فحصٍ لمشتركي الشركة [company] (null: المفتوحة كما كان).
  static DateTime? readingsAtFor(String? company) {
    if (company == null) return readingsAt;
    final at = _companyReadAt[company];
    return _fresh(at) ? at : null;
  }

  static VpnDeviceResult? deviceFor(int id) => _fresh(_devAt) ? _devices[id] : null;

  /// قراءات المشتركين من آخر فحصٍ عبر الـVPN (باليوزر صغيراً) — فارغة إن قدمت (٣٠ د).
  static Map<String, VpnSubReading> get readings => _fresh(_readAt) ? Map.unmodifiable(_readings) : const {};

  /// متى آخر فحصٍ للمشتركين عبر الـVPN.
  static DateTime? get readingsAt => _fresh(_readAt) ? _readAt : null;

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

  /// مشتركوه يُفحصون عبر الـVPN؟ (الخادم بـ«الطريق» — الوطنيّ وفايبر اكس لا: زرّ المشتركين وهنتهم وفحصهم بالوضع يختفون).
  /// «كل الشركات»: نعم — كلّ شركةٍ يقول الخادم عنها، ومن مشتركوها على شبكة الشركة تُسمّى بسببها.
  static bool get subscribersOk => _mergedNow != null || VpnNowApi.lastSubscribers;
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
    _resetBars();
    _armed = false;
    _guardAt = null;
    _via = null;
    _readings.clear();
    _devices.clear();
    _readAt = null;
    _devAt = null;
    _companyReadings.clear();
    _companyReadAt.clear();
    _companyLimits.clear();
    _companyNotes.clear();
    _route = null;
    _routeAt = null;
    VpnNowApi.lastSubscribers = true;
    subscribers.reset();
    devices.reset();
    version.value++;
  }
}
