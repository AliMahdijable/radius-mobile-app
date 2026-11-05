import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/device_config_api.dart';
import '../api/device_probe_api.dart';
import '../api/subscribers_api.dart';
import '../core/net/tcp_reachability.dart';
import '../models/subscriber.dart';
import '../screens/subscribers/widgets/device_chip_micro.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connection_readings_uploader.dart';
import 'provider_service.dart';
import 'agent_net_presence.dart';
import 'vpn_now.dart';

/// فحص أجهزة المشتركين بالخلفيّة من فتح البرنامج (٣ نوفمبر — المالك: «ليش مانخلي الدالة بالخلفية تشتغل بمجرد فتح البرنامج… حتى يكون
/// اسرع وتكون لها الاولية»).
///
/// * **بلا كلفةٍ على خادمنا:** القائمة نفسها التي تجلبها الرئيسيّة (كاش [SubscribersApi.loadAll] ٤٥ث)، والفحص لأجهزة شبكة الوكيل
///   مباشرةً — فبطاقات المشتركين تفتح بقراءاتها، و«تنبيه المشترك» التلقائيّ يقيس ولو لم تُفتح القائمة.
/// * **الأولويّة لما يفعله المستخدم:** يبدأ بعد [firstDelay] من الواجهة (لا يزاحم طلبات الرئيسيّة الأولى)، بعمّالٍ أقلّ
///   ([_workers]) من موجة القائمة، ويتوقّف فوراً حين تبدأ موجةٌ أماميّة ([DeviceProbeApi.foregroundWaves]) أو يذهب التطبيق للخلفيّة.
/// * **لا هدر:** خارج شبكة الوكيل (بيانات الهاتف) لا يردّ أيّ جهازٍ من العيّنة ([_sample]: ما ردّ سابقاً + متّصلون الآن عشوائيّاً) ⇒
///   لا موجة ويُعاد السؤال بعد [offNetRetry]؛ وما فُحص خلال ٥ دقائق لا يُعاد ([DeviceProbeApi.needsProbe])؛ والحسابات الكبيرة
///   (≥٥٠٠٠ — لا قائمة كاملة) والوطنيّ وفايبر اكس (لا عنوان جهازٍ من بوّابتهما) خارجها.
/// * الهاتف يتوقّف بالخلفيّة (النظام يعلّق الشبكة)، والحاسبة تستمرّ مصغَّرةً أو خلف نافذةٍ أخرى.
/// * كلّ [interval] موجة، وكلّ [_tick] تُقاس أجهزة «تحت المراقبة» التي حان موعد تأكيدها ([ConnectionReadingsUploader.runRechecks]).
class DeviceWarmService with WidgetsBindingObserver {
  DeviceWarmService._();
  static final DeviceWarmService _i = DeviceWarmService._();

  static const firstDelay = Duration(seconds: 8);
  static const interval = Duration(minutes: 15);
  static const _tick = Duration(seconds: 30);
  static const _workers = 12;

  /// عيّنة «هل نحن على شبكة الوكيل؟» (٣ نوفمبر — المالك: «ربما اول خمسه مبيهم وصول»): ما ردّ سابقاً أوّلاً (محفوظٌ بين
  /// الجلسات)، ثمّ متّصلون الآن مختارون من القائمة كلّها لا من أوّلها، بعنوان الجهاز الفعّال (المخصّص بمنفذه إن وُجد).
  static const _sampleKnown = 6;
  static const _sampleOnline = 8;

  /// لم يردّ أحدٌ من العيّنة ⇒ محاولةٌ بعد هذه المدّة (لا ربع ساعة): الشبكة قد تعود سريعاً.
  static const offNetRetry = Duration(minutes: 5);
  static const _goodKey = 'warm.good_ips.v1';
  static const _goodMax = 20;

  Timer? _timer;
  Timer? _first;
  DateTime? _lastWave;
  bool _running = false;
  bool _waving = false;
  bool _offNet = false;
  bool _resumed = true;

  /// الاختبار: لا مؤقّتات حقيقيّة.
  @visibleForTesting
  static bool debugDisabled = false;

  /// آخر موجةٍ بدأت (للاختبار والتشخيص).
  static DateTime? get lastWave => _i._lastWave;

  static void start() {
    // اختبارات الواجهة تبني الغلاف — لا مؤقّتات حقيقيّة فيها (والاختبار يستدعي [wave] مباشرةً)
    if (debugDisabled || _i._running || Platform.environment.containsKey('FLUTTER_TEST')) return;
    _i._running = true;
    WidgetsBinding.instance.addObserver(_i);
    _i._first = Timer(firstDelay, () => unawaited(_i._step()));
    _i._timer = Timer.periodic(_tick, (_) => unawaited(_i._step()));
  }

  static void stop() {
    if (!_i._running) return;
    _i._running = false;
    WidgetsBinding.instance.removeObserver(_i);
    _i._timer?.cancel();
    _i._first?.cancel();
    _i._timer = null;
    _i._first = null;
  }

  /// الحاسبة (ويندوز/ماك) لا يُعلّقها النظام: نافذةٌ أخرى أمامها (inactive) أو مصغَّرة (hidden) ⇒ يستمرّ — محطّة قياسٍ بالمكتب.
  /// الهاتف: النظام يوقف الشبكة والمؤقّتات بعد ثوانٍ من الخلفيّة (paused/hidden) ⇒ يتوقّف ويعود مع عودة التطبيق.
  static bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = _desktop
        ? state != AppLifecycleState.detached
        : (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive);
    if (_resumed) unawaited(_step());
  }

  bool get _yield => !_running || !_resumed || DeviceProbeApi.foregroundWaves > 0;

  /// المشروع الوطنيّ وفايبر اكس: لا عنوان جهازٍ للمشترك من بوّابتهما (جهازه تديره الشركة — «الباور» يُقرأ من البوّابة)، فلا شيء يُفحص.
  /// بقيّة الشركات المُضافة (نبض، AccessGate…) كالساس: من له عنوانٌ يُفحص.
  static bool get _providerHasDevices => !ProviderService.isFiberx && !(ProviderService.isKit && ProviderService.parentIsZone);

  Future<void> _step() async {
    if (_yield || _waving) return;
    // «وضع VPN»: الوكيل خارج شبكته والفحص من الخادم — لا موجة ولا إعادة قياسٍ من الموبايل (لا تصل شيئاً)
    if (VpnNow.mode.value) return;
    // ١) تحت المراقبة: من حان موعد تأكيده يُقاس وحده
    await ConnectionReadingsUploader.runRechecks();
    // ٢) الموجة الدوريّة
    final last = _lastWave;
    if (last != null && DateTime.now().difference(last) < (_offNet ? offNetRetry : interval)) return;
    await wave();
  }

  /// موجةٌ واحدة (تُنادى من المؤقّت، أو من الاختبار).
  @visibleForTesting
  static Future<int> wave() => _i._wave();

  Future<int> _wave() async {
    if (_waving || !_providerHasDevices) return 0;
    _waving = true;
    _lastWave = DateTime.now();
    try {
      final list = await SubscribersApi.loadAll(); // null = حسابٌ كبير أو تعذّر ⇒ لا شيء
      if (list == null || list.isEmpty || _yield) return 0;
      final subs = list.where((s) => s.companyKey == null && s.username.isNotEmpty).toList();
      final targets = subs
          .map<ProbeTarget>((s) => (username: s.username, ip: (s.ipAddress ?? '').trim(), company: null))
          .where((t) => DeviceProbeApi.needsProbe(username: t.username, ip: t.ip, company: null))
          .toList();
      if (targets.isNotEmpty) {
        // خارج شبكة الوكيل لا يردّ شيء ⇒ لا موجة (عيّنةٌ ذكيّة، ١٫٢ث بالتوازي)
        final ips = await _sample(subs);
        if (ips.isEmpty) return 0; // لا عنوان جهازٍ معروف لأحد ⇒ لا شيء يُفحص
        final ok = await Future.wait(ips.map((ip) => TcpReachability.isReachable(ip)));
        _offNet = !ok.contains(true);
        _reportPresence(ips, ok);
        if (_offNet || _yield) return 0;
        await DeviceProbeApi.warmProbe(targets, concurrency: _workers, isCanceled: () => _yield);
        DeviceProbeBus.bump();
        unawaited(_rememberGood(subs));
      }
      unawaited(ConnectionReadingsUploader.collect(subs));
      return targets.length;
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 device warm: $e');
      return 0;
    } finally {
      _waving = false;
    }
  }

  /// نتيجة [checkNow]: onNet=false ⇒ خارج شبكة الوكيل (لا جهاز من العيّنة يردّ) أو لا شيء يُفحص — [reason]: off_net · no_ips ·
  /// big (حسابٌ كبير بلا قائمةٍ كاملة) · no_devices (مزوّدٌ بلا عنوان جهاز) · error.
  @visibleForTesting
  static Future<({bool onNet, List<Subscriber> subs, int probed, String? reason})> Function(
      void Function(int done, int total)? onProgress)? debugCheckNow;

  /// «افحص الآن» (٤ نوفمبر — المالك: «من هو خارج شبكه او داخله يستدعي داله الفحص وينتظر لحد مايكمل»): فحصٌ أماميّ لكلّ أجهزة
  /// المتّصلين **من شبكة الوكيل** — مُجبَر (لا كاش) ويُنتظر. خارج الشبكة ⇒ onNet=false فيذهب المستدعي لـVPN الخادم. لا موجتان معاً:
  /// ينتظر الموجة الخلفيّة الجارية ثمّ يمسكها حتى ينتهي.
  static Future<({bool onNet, List<Subscriber> subs, int probed, String? reason})> checkNow({
    void Function(int done, int total)? onProgress,
  }) {
    final dbg = debugCheckNow;
    if (dbg != null) return dbg(onProgress);
    return _i._checkNow(onProgress);
  }

  Future<({bool onNet, List<Subscriber> subs, int probed, String? reason})> _checkNow(
      void Function(int done, int total)? onProgress) async {
    for (var i = 0; i < 120 && _waving; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _waving = true;
    try {
      if (!_providerHasDevices) return (onNet: false, subs: const <Subscriber>[], probed: 0, reason: 'no_devices');
      final list = await SubscribersApi.loadAll(); // null = حسابٌ كبير أو تعذّر
      if (list == null) return (onNet: false, subs: const <Subscriber>[], probed: 0, reason: 'big');
      final subs = list.where((s) => s.companyKey == null && s.username.isNotEmpty).toList();
      final ips = await _sample(subs);
      if (ips.isEmpty) return (onNet: false, subs: subs, probed: 0, reason: 'no_ips');
      final ok = await Future.wait(ips.map((ip) => TcpReachability.isReachable(ip)));
      _offNet = !ok.contains(true);
      _reportPresence(ips, ok);
      if (_offNet) return (onNet: false, subs: subs, probed: 0, reason: 'off_net');
      // المتّصلون الآن بعناوينهم (أجهزة المفصولين لا تردّ — تأخيرٌ بلا فائدة)؛ وإن لم تُعرف الحالة فكلّ من له عنوان
      List<Subscriber> pick(bool onlineOnly) =>
          subs.where((s) => (!onlineOnly || s.isOnline) && _effectiveIp(s).isNotEmpty).toList();
      var chosen = pick(true);
      if (chosen.isEmpty) chosen = pick(false);
      final targets = chosen.map<ProbeTarget>((s) => (username: s.username, ip: (s.ipAddress ?? '').trim(), company: null)).toList();
      await DeviceProbeApi.warmProbe(targets, force: true, onProgress: onProgress);
      DeviceProbeBus.bump();
      unawaited(_rememberGood(subs));
      _lastWave = DateTime.now();
      return (onNet: true, subs: subs, probed: targets.length, reason: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 check now: $e');
      return (onNet: false, subs: const <Subscriber>[], probed: 0, reason: 'error');
    } finally {
      _waving = false;
    }
  }

  /// الحال المشتركة (هنت «أنت خارج شبكتك») من عيّنة — العناوين الخاصّة وحدها تُحسب.
  static void _reportPresence(List<String> ips, List<bool> ok) {
    var attempted = 0, reached = 0;
    for (var i = 0; i < ips.length && i < ok.length; i++) {
      if (!AgentNetPresence.isPrivate(ips[i])) continue;
      attempted++;
      if (ok[i]) reached++;
    }
    AgentNetPresence.report(attempted: attempted, reached: reached);
  }

  static String _effectiveIp(Subscriber s) {
    final custom = DeviceConfigApi.peekConfig(s.username)?.customIp?.trim();
    return custom != null && custom.isNotEmpty ? custom : (s.ipAddress ?? '').trim();
  }

  /// «هل الهاتف على شبكة الوكيل؟» بالعيّنة نفسها (ما ردّ سابقاً + متّصلون الآن، ١٫٢ث بالتوازي) — لهنت «أنت خارج شبكتك» بقسم
  /// المشتركين (٥ نوفمبر). null: شركةٌ بلا عناوين أجهزة (الوطنيّ وفايبر اكس)، أو لا قائمة (حسابٌ كبير/تعذّر)، أو لا عنوان يُسأل.
  static Future<bool?> onAgentNetwork() {
    final f = debugPresence;
    if (f != null) return f();
    // اختبارات الواجهة تبني الشاشات — لا شبكة حقيقيّة فيها (كـ[start])
    if (debugDisabled || Platform.environment.containsKey('FLUTTER_TEST')) return Future.value(null);
    return _i._presence();
  }

  @visibleForTesting
  static Future<bool?> Function()? debugPresence;

  Future<bool?> _presence() async {
    if (!_providerHasDevices) return null;
    try {
      final list = await SubscribersApi.loadAll();
      if (list == null || list.isEmpty) return null;
      final subs = list.where((s) => s.companyKey == null && s.username.isNotEmpty).toList();
      // العناوين الخاصّة وحدها تدلّ على شبكة الوكيل (العامّ يردّ من أيّ مكان) — AgentNetPresence
      final ips = (await _sample(subs)).where(AgentNetPresence.isPrivate).toList();
      if (ips.isEmpty) return null;
      final ok = await Future.wait(ips.map((ip) => TcpReachability.isReachable(ip)));
      final reached = ok.where((x) => x).length;
      final p = AgentNetPresence.report(attempted: ips.length, reached: reached);
      _offNet = reached == 0;
      if (reached > 0) unawaited(_rememberGood(subs));
      return p == NetPresence.unknown ? null : p == NetPresence.on;
    } catch (_) {
      return null;
    }
  }

  /// العيّنة: ما ردّ في جلساتٍ سابقة (حتى [_sampleKnown]) + متّصلون الآن عشوائيّاً من القائمة كلّها (حتى [_sampleOnline])؛
  /// وإن لم يكن أيٌّ منهما فعناوين عشوائيّة من الكلّ. جهازٌ مطفأ أو بلا وصولٍ في أوّل القائمة لا يحسم شيئاً بعد اليوم.
  Future<List<String>> _sample(List<Subscriber> subs) async {
    final out = <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      out.addAll((prefs.getStringList(_goodKey) ?? const <String>[]).take(_sampleKnown));
    } catch (_) {/* بلا ذاكرة ⇒ المتّصلون وحدهم */}
    final rnd = math.Random();
    List<String> pick(Iterable<Subscriber> from, int n) {
      final ips = from.map(_effectiveIp).where((ip) => ip.isNotEmpty && !out.contains(ip)).toSet().toList()..shuffle(rnd);
      return ips.take(n).toList();
    }
    out.addAll(pick(subs.where((s) => s.isOnline), _sampleOnline));
    if (out.isEmpty) out.addAll(pick(subs, _sampleOnline));
    return out.toList();
  }

  /// عناوين أجهزةٍ قُرئت فعلاً في هذه الموجة ⇒ أوّل العيّنة في الجلسات القادمة.
  Future<void> _rememberGood(List<Subscriber> subs) async {
    final good = <String>[];
    for (final s in subs) {
      final snap = DeviceProbeApi.cachedForUser(s.username);
      if (snap != null && snap.ip.isNotEmpty) good.add(snap.ip);
      if (good.length >= _goodMax) break;
    }
    if (good.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_goodKey, good);
    } catch (_) {/* لا شيء */}
  }

  /// للاختبار: يعيد الحالة.
  @visibleForTesting
  static void debugReset() {
    debugCheckNow = null;
    stop();
    _i._lastWave = null;
    _i._waving = false;
    _i._resumed = true;
    _i._offNet = false;
  }
}
