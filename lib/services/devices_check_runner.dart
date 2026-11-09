// «الفحص الشامل» — الجلب: من شبكتك (بنك ثلاث حزم + قراءة الجهاز المفصّلة) أو عبر الـVPN («ويخضع لل vpn» — المالك ٦ نوفمبر).
// المقيِّم النقيّ في devices_check.dart؛ هنا الشبكة والتقدّم ولقطة الفحص السابق.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:dartssh2/dartssh2.dart' show SSHAuthFailError;
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/agent_alerts_api.dart';
import '../api/big_subscribers_api.dart';
import '../api/mikrotik_api.dart' show MikrotikStats;
import '../api/mikrotik_binary_api.dart' show MikrotikBinaryException;
import '../api/snmp_client.dart' show SnmpException, SnmpTimeoutException;
import '../api/subscribers_api.dart';
import '../api/vsol_olt_api.dart' show VsolOltStats;
import '../core/net/device_net.dart';
import '../models/subscriber.dart';
import '../api/network_devices_api.dart';
import '../models/network_device.dart';
import '../screens/network_devices/device_vitals.dart';
import 'connection_alerts.dart';
import 'device_stats_cache.dart';
import 'devices_check.dart';
import 'vpn_now.dart';

/// لقطة الفحص السابق لكلّ جهاز (المنافذ وعدد المتّصلين) — للمقارنة: «منفذ كان شغّال وطفى»، «نزل من 1G إلى 100M»، «السكتر فرغ».
/// معرّفات الأجهزة فريدةٌ عبر الحسابات (صفوف admin_devices) ⇒ مفتاحٌ واحد يكفي هاتفاً يدخله أكثر من مدير.
class DevicesCheckMemoStore {
  DevicesCheckMemoStore._();
  static const key = 'devices.check.last.v1';

  static Future<Map<int, CheckMemo>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return {};
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (int.tryParse('${e.key}') case final id?)
            if (CheckMemo.fromJson(e.value) case final m?) id: m,
      };
    } catch (_) {
      return {};
    }
  }

  static Future<void> save(Map<int, CheckMemo> memos) async {
    try {
      final p = await SharedPreferences.getInstance();
      final old = await load();
      old.addAll(memos);
      // سقفٌ معقول: آخر ٥٠٠ جهاز (الأقدم يُسقط) — الحساب الكبير ٣٠٠ جهاز تقريباً
      final keep = old.entries.toList();
      final trimmed = keep.length > 500 ? keep.sublist(keep.length - 500) : keep;
      await p.setString(key, jsonEncode({for (final e in trimmed) '${e.key}': e.value.toJson()}));
    } catch (_) {}
  }
}

class DevicesCheckRunner extends ChangeNotifier {
  DevicesCheckRunner(this.devices, {required this.viaVpn});

  final List<NetworkDevice> devices;

  /// عبر الخادم والـVPN (وضع VPN أو خارج شبكتك ولك طريق) — وإلّا من شبكتك مباشرة.
  final bool viaVpn;

  bool running = false;
  int done = 0;
  int get total => devices.length;

  /// سطر الحال أثناء الفحص عبر الـVPN (من شريط الـVPN نفسه).
  String? line;

  /// فشلٌ عامّ (الطريق لم يقم…) — والسبب الخادميّ لزرّ «صفحة VPN».
  String? error;
  String? errorReason;
  DateTime? at;
  final reports = <int, DeviceCheckReport>{};

  /// المشترك بيوزره — لفتح صفحته من صفّ محطّةٍ/ONU طابق ماكها ماكَ جلسته.
  final _subsByUser = <String, Subscriber>{};
  Subscriber? subscriberFor(String user) => _subsByUser[user];

  /// مشترك صفٍّ في تقرير الجهاز [deviceId] — «كل الشركات» (MergedDevicesCheckRunner) تحصره بشركة الجهاز.
  Subscriber? subscriberOn(int deviceId, String user) => subscriberFor(user);

  /// جهازٌ من شركةٍ غير المفتوحة — لا يُبحث عن مشتركه في قائمة المفتوحة.
  bool isRemote(int deviceId) => false;

  @visibleForTesting
  static Future<List<Subscriber>> Function()? debugSubscribers;

  /// ماك الجلسة ⇒ اليوزر، من قائمة الحساب المخبّأة (الحساب الكبير لا قائمة كاملة له ⇒ بلا مطابقة، والنسخ يبقى).
  Future<Map<String, String>> _macIndex() async {
    final out = <String, String>{};
    try {
      List<Subscriber>? list;
      if (debugSubscribers != null) {
        list = await debugSubscribers!();
      } else if (await BigSubscribersApi.probe().timeout(const Duration(seconds: 8)) <= 0) {
        list = await SubscribersApi.loadAllWithOnline().timeout(const Duration(seconds: 20));
      }
      for (final s in list ?? const <Subscriber>[]) {
        _subsByUser[s.username] = s;
        final m = DevicesCheck.normMac(s.lastMac);
        if (m != null) out[m] = s.username;
      }
    } catch (_) {}
    return out;
  }

  /// للاختبار: بدائل الشبكة.
  @visibleForTesting
  static Future<DeviceProbe> Function(NetworkDevice d)? debugProbe;
  @visibleForTesting
  static Future<ProbeResult> Function(NetworkDevice d)? debugFetch;
  @visibleForTesting
  static Future<CheckLimits> Function()? debugLimits;

  int _gen = 0;

  static Future<CheckLimits> loadLimits() async {
    if (debugLimits != null) return debugLimits!();
    AgentVitalsStatus? vs;
    try {
      vs = await AgentAlertsApi.vitalsStatus().timeout(const Duration(seconds: 8));
    } catch (_) {}
    var ct = ConnectionAlertThresholds.defaults;
    try {
      ct = await ConnectionAlertSettings.ensureLoaded().timeout(const Duration(seconds: 8));
    } catch (_) {}
    final s = vs?.settings;
    return CheckLimits(
      cpuMax: s?.cpuMax ?? 90,
      tempMax: s?.tempMax ?? 80,
      linkSignalMin: s?.signalMin ?? -80,
      linkCcqMin: s?.ccqMin ?? 50,
      subSignal: ct.signalDbm,
      subCcq: ct.ccqPct,
      fiberRxMin: ct.fiberRxDbm,
      voltBase: {for (final p in vs?.power ?? const <AgentVitalPower>[]) p.id: p.base},
      voltBelow: {for (final p in vs?.power ?? const <AgentVitalPower>[]) p.id: p.alertBelow},
    );
  }

  /// حدود الفحص الأخير ومطابقته بالماك — «أعد قراءة غير المقروء» لا يجلبها ثانيةً.
  ({CheckLimits limits, Map<String, String> macs})? _setup;

  Future<void> run() => _runFor(devices);

  /// «أعد قراءة غير المقروء» (٩ نوفمبر): ما لم يُقرأ وحده — والباقي يبقى بتقريره، بلا فحصٍ كامل من جديد. ويشمل ما عُرض من آخر
  /// قراءة (قراءته الجديدة لم تكتمل — المراجعة).
  Future<void> rerunUnread() {
    final again = [for (final d in devices) if (_needsRead(reports[d.id])) d];
    if (again.isEmpty) return Future<void>.value();
    return _runFor(again);
  }

  static bool _needsRead(DeviceCheckReport? r) =>
      r != null && !r.pending && (r.state == CheckState.unread || r.staleAt != null);

  /// كم جهازاً لم يُقرأ هذه المرّة («لم يُقرأ» أو من آخر قراءة) — بلا المؤقّت الجاري.
  int get unreadCount => reports.values.where(_needsRead).length;

  Future<void> _runFor(List<NetworkDevice> list) async {
    if (running) return;
    final whole = identical(list, devices);
    final gen = ++_gen;
    running = true;
    done = whole ? 0 : devices.length - list.length;
    error = null;
    errorReason = null;
    line = null;
    if (whole) reports.clear();
    _slow.clear();
    notifyListeners();
    try {
      final setup = whole ? null : _setup;
      final (limits, memos, macs) = setup != null
          ? (setup.limits, await DevicesCheckMemoStore.load(), setup.macs)
          : await (loadLimits(), DevicesCheckMemoStore.load(), _macIndex()).wait;
      _setup = (limits: limits, macs: macs);
      if (gen != _gen) return;
      if (viaVpn) {
        // ٧ نوفمبر (المالك: «كانما الوكيل يفعل vpn خارجي»): الفحص نفسه — بنكه واتّصالاته وقراءاته عبر الـVPN (DeviceNet.vpn)؛
        // الطريق أوّلاً: لا VPN أو لم يتّصل ⇒ السبب بكلمةٍ لا «كلّها طافية»
        line = 'يتّصل بالـVPN…';
        notifyListeners();
        final route = await VpnNow.pipeRoute();
        if (gen != _gen) return;
        if (!route.ok) {
          error = route.message ?? 'الـVPN ما اتّصل الآن — حاول بعد قليل';
          errorReason = route.reason;
          return;
        }
        line = null;
        await DeviceNet.vpn(() => _local(list, limits, memos, macs, gen));
      } else {
        await _local(list, limits, memos, macs, gen);
      }
      if (gen != _gen) return;
      at = DateTime.now();
      await DevicesCheckMemoStore.save({
        for (final d in list)
          if (reports[d.id]?.memo case final m?) d.id: m,
      });
    } catch (e) {
      error ??= 'تعذّر إكمال الفحص';
    } finally {
      if (gen == _gen) {
        running = false;
        notifyListeners();
      }
    }
  }

  /// أُغلق الفحص — لا كتابة بعده (القراءة المتأخّرة تُقبل ما دام الفاحص قائماً، ولو بدأ «أعد قراءة غير المقروء» بعدها).
  bool _disposed = false;

  /// قراءةٌ جارية لكلّ جهاز — «أعد قراءة غير المقروء» وفحصٌ تالٍ ينتظرانها بدل جلسةٍ ثانية على الجهاز البطيء نفسه (المراجعة).
  final _inflight = <int, _Read>{};

  @override
  void dispose() {
    _disposed = true;
    _gen++;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  // ── من شبكتك ──────────────────────────────────────────────────────

  /// أجهزةٌ تجاوزت المهلة الأولى وبسطرٍ مؤقّت تنتظر قراءتها حتى السقف — «بانتظار n أجهزة بطيئة» (٩ نوفمبر).
  final _slow = <int>{};
  Set<int> get slowPending => Set.unmodifiable(_slow);

  /// المهلة الأولى ثمّ السقف: بعد الأولى يُعرض ما عُرف («بطيء — يكمل قراءته…») ويبقى الانتظار حتى الثاني — كصفحة المشتركين
  /// (`_keepLate`): القراءة البطيئة لا تُرمى. من شبكتك ٢٥ث/٩٠ث، وعبر الممرّ ٤٥ث/١٢٠ث (كلّ رحلةٍ أطول).
  static ({Duration soft, Duration hard}) timesFor({required bool piped}) =>
      debugTimes ??
      (piped
          ? (soft: const Duration(seconds: 45), hard: const Duration(seconds: 120))
          : (soft: const Duration(seconds: 25), hard: const Duration(seconds: 90)));

  @visibleForTesting
  static ({Duration soft, Duration hard})? debugTimes;

  Future<void> _local(
      List<NetworkDevice> list, CheckLimits limits, Map<int, CheckMemo> memos, Map<String, String> macs, int gen) async {
    final queue = Queue<NetworkDevice>.from(list);
    Future<void> worker() async {
      while (queue.isNotEmpty && gen == _gen) {
        final d = queue.removeFirst();
        await _checkOne(d, limits, memos[d.id], macs, gen);
      }
    }

    // ستّةٌ معاً: القراءة المفصّلة تفتح جلسة إدارةٍ على الجهاز — لا نغرق الشبكة ولا الأجهزة الضعيفة، والنتائج تظهر أوّلاً بأوّل.
    // العامل ينتظر جهازه البطيء حتى السقف (لا جلساتٌ فوق الستّ)، وسطره المؤقّت ظاهرٌ منذ المهلة الأولى.
    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
  }

  /// مؤقّتات المهل الجارية — تُلغى بانتهاء القراءة أو بإغلاق الفحص (لا مؤقّتٌ يبقى لكلّ جهاز).
  final _timers = <Timer>{};

  /// القراءة أو انقضاء [d] أيّهما أسبق — [_Slow] حين تنقضي.
  Future<Object> _race(Future<Object> outcome, Duration d) {
    final c = Completer<Object>();
    late final Timer timer;
    timer = Timer(d, () {
      _timers.remove(timer);
      if (!c.isCompleted) c.complete(_Slow.instance);
    });
    _timers.add(timer);
    outcome.then((v) {
      timer.cancel();
      _timers.remove(timer);
      if (!c.isCompleted) c.complete(v);
    });
    return c.future;
  }

  /// تقرير الجهاز النهائيّ ⇒ القائمة والعدّاد.
  void _final(NetworkDevice d, DeviceCheckReport r, int gen) {
    if (gen != _gen) return;
    _slow.remove(d.id);
    reports[d.id] = r;
    done++;
    notifyListeners();
  }

  Future<void> _checkOne(NetworkDevice d, CheckLimits limits, CheckMemo? prev, Map<String, String> macs, int gen) async {
    bool live() => gen == _gen;
    DeviceProbe? probe;
    // عبر الـVPN كلّ رحلةٍ أطول (الموبايل ⇄ الخادم ⇄ النفق) ⇒ مهلٌ أوسع
    final piped = DeviceNet.viaPipe(d.ip);
    try {
      probe = await (debugProbe?.call(d) ?? NetworkDevicesApi.probeDevice(d, ping: true)).timeout(Duration(seconds: piped ? 25 : 15));
    } catch (_) {}
    if (!live()) return;
    final alive = switch (probe?.status) { 'online' => true, 'offline' => false, _ => null };
    if (alive == false) return _final(d, DevicesCheck.evaluate(d: d, alive: false, limits: limits, prev: prev), gen);

    // ما يمنع القراءة (بلا بيانات دخول، علامةٌ بلا مقاييس، بروتوكولٌ لا يُقرأ) — «غير متّصل/خارج شبكتك» حسمهما البنك أعلاه
    final skip = DeviceVitals.skipReason(d);
    final hard = skip == null || skip == DeviceVitals.offNetworkReason || skip == 'غير متّصل' ? null : skip;
    if (hard != null) {
      // «الحال فقط» (٩ نوفمبر): قسمٌ وحده لا «لم يُقرأ» — لا يُقرأ أصلاً بإعداده، والسبب سطره
      return _final(
          d,
          DevicesCheck.evaluate(
              d: d,
              alive: alive,
              ms: probe?.responseMs,
              loss: probe?.packetLoss,
              unreadReason: hard,
              statusOnly: true,
              limits: limits,
              prev: prev),
          gen);
    }
    final t = timesFor(piped: piped);
    final sw = Stopwatch()..start();
    // قراءةٌ جارية لهذا الجهاز (تجاوزت سقف فحصٍ سابق) ⇒ تُنتظر هي — لا جلسةٌ ثانية على الجهاز البطيء (المراجعة)
    var rd = _inflight[d.id];
    if (rd == null) {
      final fresh = rd = _Read();
      // ميكروتك: الطبقة الأولى (الموارد والصحّة والمنافذ) حين تصل — إن تأخّر الباقي يُحكم بها وعملاؤه «لم تُقرأ».
      // الأولت: الحكم من البنية، والضوء بما بقي (حتى ٥ث قبل المهلة الأولى) ويقف بإغلاق الفحص — راجع [DeviceVitals.fetch]
      final read = debugFetch?.call(d) ??
          DeviceVitals.fetch(d,
              detailed: true,
              withOnuLights: true,
              lightsUntil: DateTime.now().add(t.soft - const Duration(seconds: 5)),
              isCancelled: () => _disposed,
              onPartial: (p) => fresh.partial = p);
      fresh.outcome = read.then<Object>((p) => p, onError: (Object e) => _Failed(e));
      _inflight[d.id] = fresh;
      unawaited(fresh.outcome.whenComplete(() {
        if (identical(_inflight[d.id], fresh)) _inflight.remove(d.id);
      }));
    }
    final outcome = rd.outcome;
    final reading = rd;

    DeviceCheckReport full(ProbeResult p) => DevicesCheck.evaluate(
          d: d,
          alive: true,
          ms: probe?.responseMs,
          loss: probe?.packetLoss,
          detail: p.detail,
          raw: p.raw,
          limits: limits,
          prev: prev,
          macUsers: macs,
          readVia: viaOf(d, p.raw, piped: piped),
          readMs: sw.elapsedMilliseconds,
        );
    // ما يُعرض حين لم تكتمل القراءة: الطبقة الأولى إن وصلت (حيويّاته ومنافذه — مقروءةٌ الآن)، وإلّا آخر قراءةٍ ≤ ٥ د بعمرها
    // (ما لم يكن السبب رفضاً يُصلَح بالإعداد)، وإلّا «لم يُقرأ» بسببه
    DeviceCheckReport short(String reason, {bool pending = false}) {
      final p = reading.partial;
      final last = p == null && lastReadingHelps(reason) ? _lastReading(d) : null;
      if (last != null) {
        return DevicesCheck.evaluate(
          d: d,
          alive: true,
          ms: probe?.responseMs,
          loss: probe?.packetLoss,
          detail: last.detail,
          raw: last.raw,
          limits: limits,
          prev: prev,
          macUsers: macs,
          // العمر بالسطر نفسه (المراجعة): يبقى ظاهراً ولو كانت شارة الحال «يقرأ…»، وفي النسخ
          readNote: '${last.from} ${DevicesCheck.ago(last.at, DateTime.now())}؛ الجديدة: $reason',
          pending: pending,
          staleAt: last.at,
          staleFrom: last.from,
        );
      }
      if (p != null) {
        return DevicesCheck.evaluate(
          d: d,
          alive: true,
          ms: probe?.responseMs,
          loss: probe?.packetLoss,
          detail: p.detail,
          raw: p.raw,
          limits: limits,
          prev: prev,
          macUsers: macs,
          readNote: 'قراءةٌ جزئيّة — $reason',
          pending: pending,
          readVia: viaOf(d, p.raw, piped: piped),
          readMs: sw.elapsedMilliseconds,
        );
      }
      return DevicesCheck.evaluate(
          d: d,
          alive: alive ?? true,
          ms: probe?.responseMs,
          loss: probe?.packetLoss,
          unreadReason: reason,
          limits: limits,
          prev: prev,
          pending: pending);
    }

    // فشلٌ من داخل القارئ (المهلة الكلّيّة لا ترمي هنا — يُسابَق بها): مهلته الداخليّة تُفصل بجواب الخدمة بالبنك
    String why(Object e) {
      final r = unreadReason(e, serviceOk: probe?.serviceOk);
      // رُفض الدخول ببياناتٍ محفوظة أُعطيت لتعثّر الخادم ⇒ ليس «تأكّد من الرمز» (قد تكون عُدّلت) — المراجعة
      return r == _login && NetworkDevicesApi.servedStaleCredentials(d.id) ? _loginStale : r;
    }

    // ١) المهلة الأولى
    final first = await _race(outcome, t.soft);
    if (!live()) return;
    if (first is ProbeResult) return _final(d, full(first), gen);
    if (first is _Failed) return _final(d, short(why(first.error)), gen);

    // ٢) بطيء: سطرٌ مؤقّت بما عُرف، والانتظار حتى السقف
    _slow.add(d.id);
    reports[d.id] = short('بطيء — يكمل قراءته (تجاوز ${t.soft.inSeconds}ث)…', pending: true);
    notifyListeners();
    final second = await _race(outcome, t.hard - t.soft);
    if (!live()) return;
    if (second is ProbeResult) return _final(d, full(second), gen);
    if (second is _Failed) return _final(d, short(why(second.error)), gen);

    // ٣) السقف: «بطيء» بثوانيه — وما يصل بعده يُحفظ ويحلّ محلّه ما دام الفحص نفسه قائماً (لا يُرمى)
    final capped = short('بطيء — لم تكتمل قراءته خلال ${t.hard.inSeconds}ث');
    _final(d, capped, gen);
    // الهويّة وحدها تحرس (لا رقم الجولة): فحصٌ كامل جديد يمسح التقارير، وتقريرٌ أحدث يحلّ محلّه — و«أعد قراءة غير المقروء» لأجهزةٍ
    // أخرى لا يُسقط ما وصل لهذا (المراجعة)
    unawaited(outcome.then((late) {
      if (late is! ProbeResult || _disposed || !identical(reports[d.id], capped)) return;
      final r = full(late);
      reports[d.id] = r;
      if (r.memo != null) unawaited(DevicesCheckMemoStore.save({d.id: r.memo!}));
      notifyListeners();
    }));
  }

  /// طريق القراءة كما يُكتب على السطر — ما يُعرف وحده: ميكروتك من جلسته، والأولت وميموزا وروجي SNMP، وسسكو ببروتوكوله؛
  /// وعبر ممرّ الـVPN يُقال. يوبيكويتي (SSH أو ويب الطُرُز الجديدة) لا يُخمَّن.
  @visibleForTesting
  static String? viaOf(NetworkDevice d, Object? raw, {required bool piped}) {
    final b = d.brand.toLowerCase();
    final v = raw is MikrotikStats
        ? raw.via
        : raw is VsolOltStats || b == 'mimosa' || b == 'ruijie'
            ? 'SNMP'
            : b == 'cisco'
                ? (d.protocol == 'telnet' ? 'Telnet' : 'SSH')
                : null;
    if (!piped) return v;
    return v == null ? 'عبر الـVPN' : '$v عبر الـVPN';
  }

  // ── آخر قراءة (٩ نوفمبر) ──────────────────────────────────────────

  /// آخر قراءةٍ لهذا الجهاز عمرها ≤ ٥ دقائق — حين لا تكتمل قراءة الفحص («كلّما عرضت البطاقة أرقاماً عرضها الفحص»): المعروضة
  /// (البطاقة الكبيرة، البرج، شاشات الألياف)، ثمّ الخفيفة الخام (التسخين — ميكروتك والأولت)، ثمّ عبر الـVPN ما قرأه الخادم.
  /// تُعرض بعمرها ولا تكتب اللقطة ([DevicesCheck.evaluate] staleAt).
  ({DeviceDetail detail, Object? raw, DateTime at, String from})? _lastReading(NetworkDevice d) {
    const maxAge = Duration(minutes: 5);
    final shown = DeviceStatsCache.instance.vitalsOf(d.id, maxAge);
    final det = shown?.detail;
    if (shown != null && det is DeviceDetail && _hasNumbers(det)) return (detail: det, raw: null, at: shown.at, from: 'آخر قراءة');
    // الخام الكاملة قد تحمل لحظةً جدّدتها قراءةٌ خفيفة ([DeviceStatsCache.rawOf]) — فالخفيفة وحدها (أرقامها بلحظتها)
    final raw = DeviceStatsCache.instance.rawOf(d.id, maxAge);
    if (raw != null && !raw.detailed) {
      final r = raw.raw;
      final p = r is MikrotikStats
          ? DeviceVitals.mikrotikResult(d, r, null, detailed: false)
          : (r is VsolOltStats ? oltProbeResult(r) : null);
      if (p != null && _hasNumbers(p.detail)) return (detail: p.detail, raw: r, at: raw.at, from: 'آخر قراءة');
    }
    if (viaVpn) {
      // لحظة قراءة الخادم (المراجعة — لا لحظة وصولها للتطبيق): من الجهاز إن أعطاها، وإلّا نهاية فحصه (`at_ms`) ناقص نافذة إعادة
      // استعماله للقراءات — الأقدم المحتمل، فلا تُقدَّم أحدث ممّا هي. وملخّص الأولت قد يبلغ ٣٠ د بلا لحظته ⇒ لا يُستعمل.
      final r = VpnNow.deviceFor(d.id);
      final v = r?.vitals;
      final own = r?.readAtMs;
      final at = own != null ? DateTime.fromMillisecondsSinceEpoch(own) : VpnNow.devicesServerAt?.subtract(serverVitalsReuse);
      final olt = '${v?['kind'] ?? ''}' == 'olt';
      if (v != null && at != null && (own != null || !olt) && DateTime.now().difference(at) <= maxAge) {
        final det = DeviceVitals.fromVpn(v, at: at).detail;
        if (det != null && _hasNumbers(det)) return (detail: det, raw: null, at: at, from: 'آخر قراءة من فحص الخادم');
      }
    }
    return null;
  }

  /// كم تُعاد قراءةٌ لجهازٍ بفحص الخادم قبل أن تُقرأ من جديد (`VITALS_EVERY_MS` بـserver/connVpn/sweeper.js) — قراءةٌ في نتيجة فحصٍ
  /// قد تكون أقدم منه بهذا القدر.
  static const serverVitalsReuse = Duration(seconds: 150);

  @visibleForTesting
  ({DeviceDetail detail, Object? raw, DateTime at, String from})? lastReadingFor(NetworkDevice d) => _lastReading(d);

  /// تفصيلٌ يحمل رقماً واحداً على الأقلّ — «سليم» من قراءةٍ فارغة ادّعاء.
  static bool _hasNumbers(DeviceDetail x) {
    final g = x.glance;
    return x.ports.isNotEmpty ||
        x.peers.isNotEmpty ||
        g.cpu != null ||
        g.mem != null ||
        g.temp != null ||
        g.signal != null ||
        g.onusTotal != null ||
        g.uptimeSec != null;
  }

  // ── لماذا لم يُقرأ ────────────────────────────────────────────────

  static const _service = 'يردّ، لكن خدمة الإدارة لا تجيب — تأكّد من المنفذ والبروتوكول';
  static const _login = 'يردّ، لكن رُفض الدخول — تأكّد من اسم المستخدم والرمز';
  static const _loginStale = 'رُفض الدخول ببيانات دخولٍ محفوظة (الخادم ما ردّ وقتها) — أعد الفحص بعد قليل';
  static const _permission = 'يردّ، لكن مستخدمه بلا صلاحيّة قراءة — راجع صلاحيّاته على الجهاز';
  static const _noCreds = 'بيانات دخوله ناقصة — أكملها من صفحة الجهاز';
  static const _unsupported = 'علامته لا تُقرأ بالفحص';

  /// آخر قراءةٍ تنفع مع هذا السبب؟ لا مع ما يُصلَح بالإعداد (رفض الدخول، الصلاحيّة، النقص) — يُقال وحده بلا أرقامٍ قديمة تغطّيه.
  @visibleForTesting
  static bool lastReadingHelps(String reason) =>
      !const {_login, _loginStale, _permission, _noCreds, _unsupported}.contains(reason);

  /// لماذا لم تُقرأ معلومات جهازٍ يردّ — السبب الحقيقيّ بكلمة.
  ///
  /// ٩ نوفمبر (المالك: «مرات اكو اجهزه بالنظام يتفحها ويعرض معلومات بس بقسم فحص الاجهزه يكول لم يقرا»): كان كلّ فشلٍ «تأكّد من
  /// اسم المستخدم والرمز» — ومهلة الجهاز البطيء، والمنفذ المقفول، وزحمة ممرّ الـVPN، وتعذّر جلب بيانات الدخول من خادمنا كلّها غيره.
  /// رسالة الدخول الآن لرفض الدخول الحقيقيّ وحده. [deadline] مهلة القراءة كلّها (ث) حين تكون [e] هي (null = فشلٌ من داخل
  /// القارئ)، و[serviceOk] جواب خدمة الإدارة بالبنك (null = لم يُعرف) — يفصل «بطيء» عن «لا يُفتح» حين تأتي المهلة من الداخل.
  @visibleForTesting
  static String unreadReason(Object e, {int? deadline, bool? serviceOk}) {
    // ١) المهلة كلّها — الجهاز يردّ لكنّ قراءته الكاملة أطول منها
    if (e is TimeoutException && deadline != null) return 'بطيء — لم تكتمل قراءته خلال $deadlineث';
    final s = e.toString();
    final low = s.toLowerCase();
    // ٢) ممرّ الـVPN وخادمنا (رسائل الخادم كما هي: «اتّصالاتٌ كثيرة الآن — لحظات»، «الـVPN ما اتّصل الآن…»)
    if (s.contains('اتّصالاتٌ كثيرة') || s.contains('اتّصالات كثيرة') || low.contains('pipe_busy')) {
      return 'اتّصالات كثيرة عبر الـVPN الآن — أعد الفحص بعد قليل';
    }
    if (s.contains('الـVPN ما اتّصل') || s.contains('تعذّر الوصول للخادم') || s.contains('تعذّر فتح الممرّ')) {
      return 'ممرّ الـVPN ما ردّ لحظتها — أعد الفحص بعد قليل';
    }
    // ٣) رُفض الدخول فعلاً (ميكروتك code=auth، SSH، ويب يوبيكويتي، سسكو)
    if ((e is MikrotikBinaryException && e.code == 'auth') ||
        e is SSHAuthFailError ||
        s.contains('اسم المستخدم أو كلمة') ||
        (s.contains('رُفض') && s.contains('اسم المستخدم')) ||
        low.contains('auth failed') ||
        low.contains('invalid user name or password')) {
      return _login;
    }
    // ٤) دخل وصلاحيّته لا تكفي للقراءة (مجموعة المستخدم، community بلا قراءة)
    if (low.contains('not enough permissions') || s.contains('صلاحيّة القراءة') || s.contains('صلاحيّات المستخدم')) {
      return _permission;
    }
    // ٥) بيانات دخوله من خادمنا: الطلب فشل (٥٠٣ عابرة…) أو ناقصة
    if (e is DioException || s.contains('فشل جلب المعلومات')) {
      return 'تعذّر جلب بيانات دخوله من الخادم — أعد الفحص بعد قليل';
    }
    if (s.contains('بيانات دخول ناقصة') ||
        s.contains('لم يتم إعداد بيانات الدخول') ||
        s.contains('لم تُحفظ الـcommunity') ||
        s.contains('أدخل الـcommunity')) {
      return _noCreds;
    }
    if (s.contains('غير مدعومة')) return _unsupported;
    final inTime = e is TimeoutException ||
        e is SnmpTimeoutException ||
        low.contains('timeout') ||
        low.contains('timed out') ||
        s.contains('مهلة') ||
        s.contains('لا ردّ');
    // ٦) SNMP لم يجب: الـcommunity/المنفذ — إلّا إن أجاب البنكَ بالـcommunity نفسها (بطيءٌ إذن)
    if (inTime && (e is SnmpException || s.contains('SNMP'))) {
      return serviceOk == true ? 'بطيء — ما كمّل جوابه بالوقت' : 'يردّ، لكن SNMP ما جاوب — تأكّد من الـcommunity والمنفذ';
    }
    // ٧) منفذ الإدارة لا يُفتح (رفض، لا طريق، مهلة اتّصال)
    if (e is SocketException ||
        low.contains('refused') ||
        low.contains('unreachable') ||
        low.contains('no route') ||
        s.contains('رفض الاتصال') ||
        s.contains('غير قابل') ||
        s.contains('تعذّر الوصول') ||
        s.contains('تعذّر فتح') ||
        s.contains('مغلق')) {
      return _service;
    }
    // ٨) مهلةٌ من داخل القارئ: بطيءٌ ما دامت خدمته أجابت البنك
    if (inTime) return serviceOk == false ? _service : 'بطيء — ما كمّل جوابه بالوقت';
    return serviceOk == false ? _service : 'يردّ، لكن ما انقرت معلوماته';
  }
}

/// قراءةٌ فشلت — بسببها (لا يُخلط بالمهلة).
class _Failed {
  const _Failed(this.error);
  final Object error;
}

/// انقضت المهلة والقراءة لم تكتمل.
class _Slow {
  const _Slow._();
  static const instance = _Slow._();
}

/// قراءة جهازٍ جارية: نتيجتها (أو فشلها) وطبقتها الأولى إن وصلت.
class _Read {
  late Future<Object> outcome;
  ProbeResult? partial;
}
