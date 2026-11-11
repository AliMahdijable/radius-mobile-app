import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../api/network_devices_api.dart';
import '../../../models/network_device.dart';
import '../../../services/agent_net_presence.dart';
import '../../../services/deep_probe_scheduler.dart';
import '../../../services/device_read_health.dart';
import '../../../services/device_stats_cache.dart';
import '../../../services/device_sweep_coordinator.dart';
import '../../../services/vpn_now.dart';
import '../device_vitals.dart';
import 'tower_logic.dart';
import 'tower_reading.dart';

/// قراءات أطراف اللنكات لشاشة «الترابط» — بقواعد البرج نفسها ([TowerScreen])، محصورةً بأطراف اللنكات:
///
/// * القراءة من جلسة قسم الأجهزة ([DeviceVitals.fetch]) عبر [DeepProbeScheduler]، وتُكتب في [DeviceStatsCache] فلا تُدفع مرّتين.
/// * «لا يردّ» لا يُقال بلقطة السجلّ: بفحص وصولٍ خفيف نجريه نحن ([NetworkDevicesApi.probeDevice]) ويُعاد كلّ ~٣٠ث ([ReachVerdict]).
///   (المالك ١١ نوفمبر عن تنبيهات الأجهزة: «غير دقيقة» — جهازٌ يعمل قيل عنه طافٍ من حكمٍ قديم.)
/// * رقمٌ قديم ليس رقماً: قراءةٌ فشلت بعدها القراءة، أو أقدم من [freshFor]، لا تُعرض.
/// * خارج شبكة الوكيل (بلا «وضع VPN») لا جلسة تصل ولا حكم — [offNetwork]، والشاشة تقولها بدل «واقع» على كلّ شيء.
///
/// باقي الأجهزة ([setDevices] `others`) لا تُقرأ دوريّاً: تُبذَر ممّا قرأه القسم ([DeviceStatsCache]) ومرّةً واحدة لما طُلب
/// ([setDevices] `scanOnce` — صحون اللنكات غير المربوطة) لاقتراح الوصلات.
class TowerLinkProbe extends ChangeNotifier {
  TowerLinkProbe({this.refreshEvery = const Duration(seconds: 20)});

  final Duration refreshEvery;

  /// عمر القراءة التي تُعرض رقماً حيّاً — نافذة بذر القسم نفسها.
  static const freshFor = DeviceStatsCache.seedTtl;

  /// أقصى ما يُقرأ مرّةً لاقتراح الوصلات.
  static const scanCap = 16;

  /// السرعة فرقُ عدّادين: أوّل قراءةٍ لطرفٍ بلا عيّنةٍ سابقة لا تحمل سرعة. فتُعاد قراءته مرّةً بعد هذه المدّة — يظهر ما يعبر
  /// اللنك خلال ثوانٍ لا بعد الدورة التالية (٢٠ث).
  static const firstRateAfter = Duration(seconds: 4);

  Map<int, NetworkDevice> _ends = const {};
  Map<int, NetworkDevice> _others = const {};
  final Map<int, TowerReading> _readings = {};
  final Map<int, DateTime> _failedSince = {};
  final Map<int, TowerReach> _reach = {};
  final Set<int> _reaching = {};
  final Set<int> _inFlight = {};

  /// من ينتظر القراءة الجارية على جهاز ([readOnce] والدورة تقرؤه)، وقراءات [readOnce] المعلّقة بمالكها في الطابور.
  final Map<int, List<Completer<void>>> _landing = {};
  final Map<Object, Completer<TowerReading?>> _once = {};
  final Set<int> _scanned = {};
  final Map<int, Timer> _followUps = {};
  final Set<int> _followed = {};
  final Map<int, Object> _owners = {};
  Timer? _timer;
  Timer? _flush;
  bool _running = false;
  bool _disposed = false;

  Object _ownerOf(int id) => _owners[id] ??= Object();

  /// خارج شبكة الأجهزة ولا «وضع VPN» — لا شيء يُقرأ ولا يُحكم.
  bool get offNetwork => !VpnNow.devicesMode && AgentNetPresence.isOff;

  /// قراءة جهازٍ إن كانت حيّة: لم تفشل بعدها قراءة، وعمرها ضمن [freshFor].
  TowerReading? readingOf(int id) {
    if (_failedSince.containsKey(id)) return null;
    final r = _readings[id];
    if (r == null || DeviceReadHealth.clock().difference(r.at) > freshFor) return null;
    return r;
  }

  /// كلّ ما عندنا من قراءات (أطرافاً وغيرها) — لاقتراح الوصلات.
  Map<int, TowerReading> get known => Map.unmodifiable(_readings);

  /// «لا يردّ» بحكم فحصٍ حديثٍ أجريناه — لقطة السجلّ وحدها لا تكفي.
  bool isDown(int id) {
    if (offNetwork) return false;
    final v = _reach[id];
    return v != null && !v.reachable && DeviceReadHealth.clock().difference(v.at) <= ReachVerdict.validFor;
  }

  /// يردّ على الفحص وقراءته تفشل — إعداداته (كلمة المرور/المنفذ) لا الجهاز.
  bool needsSettings(int id) {
    final since = _failedSince[id];
    final v = _reach[id];
    return since != null &&
        v != null &&
        v.reachable &&
        ReachVerdict.covers(checkedAt: v.at, since: since, now: DeviceReadHealth.clock());
  }

  /// لمَ لا يُقرأ هذا الطرف أصلاً (بلا بيانات دخول، علامة بلا مقاييس…) — null: يُقرأ.
  String? skipReasonOf(int id) {
    final d = _ends[id];
    if (d == null) return null;
    final why = DeviceVitals.skipReason(d.copyWith(lastStatus: 'online'));
    return why == DeviceVitals.offNetworkReason ? null : why;
  }

  /// [ends] أطراف اللنكات (تُقرأ كلّ دورة)، [others] تُبذَر من المخزن، [scanOnce] تُقرأ مرّةً (حتى [scanCap]).
  void setDevices({
    required Iterable<NetworkDevice> ends,
    Iterable<NetworkDevice> others = const [],
    Iterable<NetworkDevice> scanOnce = const [],
  }) {
    final before = _ends;
    final next = <int, NetworkDevice>{};
    for (final d in ends) {
      final old = before[d.id];
      // جهازٌ تغيّر عنوانه: حكمه وفشله كانا لعنوانٍ آخر
      if (old != null && old.ip != d.ip) {
        _reach.remove(d.id);
        _failedSince.remove(d.id);
        _readings.remove(d.id);
      }
      // حكمنا الحديث أصدق من لقطة الخادم
      final v = _reach[d.id];
      final fresh = v != null && DeviceReadHealth.clock().difference(v.at) <= ReachVerdict.validFor;
      next[d.id] = fresh ? d.copyWith(lastStatus: v.reachable ? 'online' : 'offline') : d;
    }
    _ends = next;
    _others = {
      for (final d in others)
        if (!next.containsKey(d.id)) d.id: d,
    };
    for (final id in _owners.keys.toList()) {
      if (!next.containsKey(id) && !_others.containsKey(id)) {
        DeepProbeScheduler.instance.cancel(_owners.remove(id)!);
        // مهمّةٌ سُحبت قبل أن تبدأ لا يصلها `finally` — وإلّا بقي الجهاز «قيد القراءة» ولم يُقرأ إن رُبط من جديد
        _land(id);
        _readings.remove(id);
        _failedSince.remove(id);
        _reach.remove(id);
      }
    }
    for (final id in _followUps.keys.toList()) {
      if (!next.containsKey(id)) _followUps.remove(id)!.cancel();
    }
    _followed.removeWhere((id) => !next.containsKey(id));
    for (final d in [...next.values, ..._others.values]) {
      _seed(d.id);
    }
    if (!_running) return;
    // أطرافٌ جديدة تُقرأ الآن؛ اللقطة نفسها (تحديث حال الأجهزة كلّ ٣٠ث) لا تفتح دورةً زائدة
    if (next.keys.any((id) => !before.containsKey(id))) _probe(first: true);
    var n = _scanned.length;
    for (final d in scanOnce) {
      if (n >= scanCap) break;
      if (next.containsKey(d.id) || !_scanned.add(d.id)) continue;
      n++;
      if (d.lastStatus != 'offline' && !_readings.containsKey(d.id)) _read(d);
    }
  }

  void start() {
    if (_running || _disposed) return;
    _running = true;
    DeviceStatsCache.instance.updated.addListener(_onCacheUpdated);
    _probe(first: true);
    _timer = Timer.periodic(refreshEvery, (_) => _probe());
  }

  void stop() {
    if (!_running) return;
    _running = false;
    DeviceStatsCache.instance.updated.removeListener(_onCacheUpdated);
    _timer?.cancel();
    _timer = null;
    for (final t in _followUps.values) {
      t.cancel();
    }
    _followUps.clear();
  }

  /// قراءةٌ واحدة مفصّلة لجهازٍ **الآن** — لمنتقي منفذ الكيبل الضوئيّ (منافذ السويج بحالها وما يعبرها)، أيّاً كان الجهاز
  /// (طرف وصلةٍ أو لا). بطابور القسم نفسه ومخزنه، فلا تُدفع الجلسة مرّتين. تُرجع ما قُرئ، أو آخر ما عندنا إن لم يُقرأ
  /// (خارج الشبكة، بلا بيانات دخول، تعذّر الاتّصال) — وnull إن لم يكن عندنا شيء.
  Future<TowerReading?> readOnce(NetworkDevice d) async {
    if (_disposed) return null;
    TowerReading? last() => _disposed ? null : _readings[d.id];
    if (DeviceVitals.skipReason(d.copyWith(lastStatus: 'online')) != null || DeviceSweep.suspended || DeviceSweep.busy(d.id)) {
      return last();
    }
    // الدورة تقرؤه الآن (طرف وصلة) — تُنتظر قراءتها، لا جلسةٌ ثانية على الجهاز نفسه
    if (_inFlight.contains(d.id)) {
      final landed = Completer<void>();
      (_landing[d.id] ??= []).add(landed);
      await landed.future.timeout(readOnceTimeout, onTimeout: () {});
      return last();
    }
    _inFlight.add(d.id);
    final owner = Object();
    final done = Completer<TowerReading?>();
    _once[owner] = done;
    DeepProbeScheduler.instance.submit(owner, first: true, () async {
      try {
        final prev = DeviceStatsCache.instance.sampleOf(d.id);
        final r = await DeviceVitals.fetch(
          d,
          prev: prev == null ? null : CounterSample(prev.counters, prev.at),
          detailed: true,
        );
        if (r.raw != null) DeviceStatsCache.instance.putRaw(d.id, r.raw!, detailed: true);
        DeviceStatsCache.instance.putVitals(d.id, r.vitals, r.detail);
        DeviceStatsCache.instance.putSample(d.id, r.counters);
        final reading = TowerReading.fromProbe(r);
        if (!_disposed) {
          _readings[d.id] = reading;
          DeviceReadHealth.instance.ok(d.id);
          if (_ends.containsKey(d.id)) {
            _failedSince.remove(d.id);
            _reached(d.id);
          }
          _scheduleFlush();
        }
        if (!done.isCompleted) done.complete(reading);
      } catch (_) {
        // قراءةٌ بطلب المنتقي: فشلها يقوله المنتقي نفسه («تعذّرت قراءة منافذه») — لا يُسجَّل على الجهاز عطلاً
        if (!done.isCompleted) done.complete(last());
      } finally {
        _once.remove(owner);
        _land(d.id);
      }
    });
    // مهمّةٌ علقت جلستها لا تُبقي المنتقي يدور — ولا تحجز الجهاز عن دورة القراءة
    return done.future.timeout(readOnceTimeout, onTimeout: () {
      _once.remove(owner);
      _land(d.id);
      return last();
    });
  }

  /// أقصى انتظار [readOnce].
  static const readOnceTimeout = Duration(seconds: 25);

  /// انتهت القراءة الجارية على الجهاز (نجحت أو لا) — يُفرج عنه ويُنبَّه من ينتظرها.
  void _land(int id) {
    _inFlight.remove(id);
    final waiting = _landing.remove(id);
    if (waiting == null) return;
    for (final w in waiting) {
      if (!w.isCompleted) w.complete();
    }
  }

  /// الآن لا بعد الدورة (رجع من صفحة جهاز، أو سحب للتحديث).
  void refreshNow({int? only}) {
    if (!_running) return;
    for (final d in _ends.values) {
      if (only != null && d.id != only) continue;
      if (d.lastStatus == 'offline' || _failedSince.containsKey(d.id)) _checkReach(d, force: true);
    }
    _probe(only: only);
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _flush?.cancel();
    for (final o in _owners.values) {
      DeepProbeScheduler.instance.cancel(o);
    }
    // قراءات المنتقي المعلّقة ومن ينتظر: تُسحب وتُجاب بلا شيء — لا مؤقّت يبقى بعد الشاشة
    for (final e in _once.entries.toList()) {
      DeepProbeScheduler.instance.cancel(e.key);
      if (!e.value.isCompleted) e.value.complete(null);
    }
    _once.clear();
    for (final id in _landing.keys.toList()) {
      _land(id);
    }
    super.dispose();
  }

  void _seed(int id) {
    if (_readings.containsKey(id)) return;
    final v = DeviceStatsCache.instance.vitalsOf(id, DeviceStatsCache.seedTtl);
    final detail = v?.detail;
    if (v == null || detail is! DeviceDetail) return;
    if (detail.ports.isEmpty && detail.peers.isEmpty) return;
    _readings[id] = TowerReading.fromProbe(
      ProbeResult(vitals: const [], detail: detail, counters: const {}, raw: DeviceStatsCache.instance.seedFor<Object>(id)),
      at: v.at,
    );
  }

  /// قرأ القسمُ (برجٌ أو الجدار) جهازاً نراقبه أحدث ممّا عندنا ⇒ من المخزن فوراً.
  void _onCacheUpdated() {
    if (_disposed) return;
    final id = DeviceStatsCache.instance.updated.value.id;
    if (!_ends.containsKey(id) && !_others.containsKey(id)) return;
    final v = DeviceStatsCache.instance.vitalsOf(id, DeviceStatsCache.seedTtl);
    final detail = v?.detail;
    if (v == null || detail is! DeviceDetail) return;
    // بطاقة الجدار المطويّة تقرأ الخانات الثلاث وحدها (بلا منافذ ولا عملاء) — لا تحلّ محلّ القراءة الكاملة
    if (detail.ports.isEmpty && detail.peers.isEmpty) return;
    final cur = _readings[id];
    if (cur != null && !v.at.isAfter(cur.at)) return;
    _readings[id] = TowerReading.fromProbe(
      ProbeResult(vitals: const [], detail: detail, counters: const {}, raw: DeviceStatsCache.instance.seedFor<Object>(id)),
      at: v.at,
    );
    if (_ends.containsKey(id)) {
      _failedSince.remove(id);
      _reached(id);
    }
    _scheduleFlush();
  }

  void _probe({bool first = false, int? only}) {
    // «الفحص الشامل» يجري — لا قراءات مفصّلة على أجهزته نفسها (كالبرج)
    if (DeviceSweep.suspended) return;
    for (final d in _ends.values) {
      if (only != null && d.id != only) continue;
      // لا يردّ (لقطة السجلّ أو فحصنا): فحص وصولٍ خفيف كلّ ~٣٠ث، ويُقرأ حين يعود
      if (d.lastStatus == 'offline') {
        _checkReach(d);
        continue;
      }
      _read(d, first: first && !_readings.containsKey(d.id));
    }
  }

  void _read(NetworkDevice d, {bool first = false}) {
    if (_inFlight.contains(d.id)) return;
    if (DeviceVitals.skipReason(d) != null) return;
    if (DeviceSweep.busy(d.id)) return;
    _inFlight.add(d.id);
    DeepProbeScheduler.instance.submit(_ownerOf(d.id), first: first, () async {
      try {
        if (DeviceSweep.suspended || DeviceSweep.busy(d.id)) return;
        final prev = DeviceStatsCache.instance.sampleOf(d.id);
        final r = await DeviceVitals.fetch(
          d,
          prev: prev == null ? null : CounterSample(prev.counters, prev.at),
          detailed: true,
        );
        // المخزن عالميّ: يُكتب ولو غادر المستخدم — جلسةٌ دُفع ثمنها لا تُرمى
        if (r.raw != null) DeviceStatsCache.instance.putRaw(d.id, r.raw!, detailed: true);
        DeviceStatsCache.instance.putVitals(d.id, r.vitals, r.detail);
        DeviceStatsCache.instance.putSample(d.id, r.counters);
        if (_disposed) return;
        _readings[d.id] = TowerReading.fromProbe(r);
        DeviceReadHealth.instance.ok(d.id);
        if (_ends.containsKey(d.id)) {
          _failedSince.remove(d.id);
          _reached(d.id);
          // أوّل قراءةٍ بلا عيّنةٍ سابقة لا سرعة فيها — تُعاد مرّةً بعد ثوانٍ
          if (prev == null && _running && _followed.add(d.id)) {
            _followUps[d.id] = Timer(firstRateAfter, () {
              _followUps.remove(d.id);
              final cur = _ends[d.id];
              if (!_disposed && _running && cur != null && cur.lastStatus != 'offline') _read(cur);
            });
          }
        }
        _scheduleFlush();
      } catch (_) {
        if (_disposed || !_ends.containsKey(d.id)) return;
        DeviceReadHealth.instance.failed(d.id, 'تعذّر الاتّصال');
        _failedSince[d.id] ??= DeviceReadHealth.clock();
        // مطفأ أم إعداداته؟ لا يُقال شيءٌ قبل أن يجيب فحص الوصول
        _checkReach(d);
        _scheduleFlush();
      } finally {
        _land(d.id);
      }
    });
  }

  void _checkReach(NetworkDevice d, {bool force = false}) {
    final id = d.id;
    if (_reaching.contains(id) || offNetwork) return;
    if (!force && !ReachVerdict.due(checkedAt: _reach[id]?.at, since: _failedSince[id], now: DeviceReadHealth.clock())) return;
    _reaching.add(id);
    _runReach(d);
  }

  Future<void> _runReach(NetworkDevice d) async {
    try {
      final r = await NetworkDevicesApi.probeDevice(d);
      if (_disposed || !_ends.containsKey(d.id)) return;
      final ok = r.status == 'online';
      _reach[d.id] = (reachable: ok, at: DeviceReadHealth.clock());
      final wasDown = _setStatus(d.id, ok ? 'online' : 'offline');
      _scheduleFlush();
      // عاد يردّ ⇒ يُقرأ الآن لا بعد الدورة القادمة
      if (ok && wasDown) _probe(only: d.id);
    } catch (_) {
      // فحصٌ فشل بلا حكم — يبقى مجهولاً حتى الفحص التالي
    } finally {
      _reaching.remove(d.id);
    }
  }

  void _reached(int id) {
    _reach[id] = (reachable: true, at: DeviceReadHealth.clock());
    _setStatus(id, 'online');
  }

  /// يُرجع: كان «لا يردّ» قبلها؟
  bool _setStatus(int id, String status) {
    final cur = _ends[id];
    if (cur == null) return false;
    final wasDown = cur.lastStatus == 'offline';
    if (cur.lastStatus != status) _ends = {..._ends, id: cur.copyWith(lastStatus: status)};
    return wasDown;
  }

  // دفعةٌ كلّ ٤٠٠ms بدل إعادة بناءٍ لكلّ جهاز (كالبرج والجدار)
  void _scheduleFlush() {
    if (_disposed || (_flush?.isActive ?? false)) return;
    _flush = Timer(const Duration(milliseconds: 400), () {
      if (!_disposed) notifyListeners();
    });
  }
}
