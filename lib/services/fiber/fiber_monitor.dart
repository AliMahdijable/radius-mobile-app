import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/bdcom_epon.dart';
import '../../api/bridge_fdb.dart';
import '../../api/broadcast_api.dart';
import '../../api/fiber_api.dart';
import '../../api/network_devices_api.dart';
import '../../api/olt_fiber_reads.dart';
import '../../api/olt_profile.dart';
import '../../api/snmp_client.dart';
import '../../api/vsol_gpon_details.dart';
import '../../api/vsol_olt_api.dart';
import '../../models/fiber_network.dart';
import '../../models/network_device.dart';
import '../device_stats_cache.dart';
import 'fiber_band.dart';
import 'fiber_onu.dart';
import 'fiber_outage.dart';
import 'fiber_store.dart';
import 'fiber_text.dart';

/// مصدر قراءة الأولت — SNMP الحقيقيّ، وللاختبار بديلٌ يعيد لقطاتٍ جاهزة.
class FiberBackend {
  const FiberBackend();

  Future<String?> community(NetworkDevice d) async {
    final c = await NetworkDevicesApi.getCredentials(d.id);
    final v = (c['community'] ?? c['pass'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }

  SnmpV2c snmp(NetworkDevice d, String community) => SnmpV2c(host: d.ip, port: d.apiPort ?? 161, community: community);

  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p) => VsolOltApi.fetchStats(
        host: d.ip,
        port: d.apiPort ?? 161,
        community: community,
        structureOnly: true,
        withCounters: false,
        withGponDetails: false,
        profile: p,
      );

  Future<VsolOltStats> hot(NetworkDevice d, String community, VsolOltStats prev) =>
      VsolOltApi.refreshHotCounters(host: d.ip, port: d.apiPort ?? 161, community: community, previous: prev);
}

/// مراقب أولتٍ واحد لشبكة الألياف: الحالة كلّ ١٥ث، والضوء كلّ دقيقة، وسبب السقوط ولحظته عند كلّ تغيّر، والأجهزة خلف كلّ
/// ONU حين تُطلب ([wantDevices])، ثمّ كشف الأعطال وتبليغ الخادم (فيصل الإشعار لكلّ أجهزة الحساب).
///
/// يعمل ما دام له مستخدم ([acquire]/[release]): شاشات الألياف على الهاتف، والحاسبة بالخلفيّة ([background]، إيقاعٌ أبطأ).
/// لا يكتب في [DeviceStatsCache] (لقطةٌ بلا عدّادات تُفقر لوحة الأولت) — يقرأ منه بذرةً فقط.
class FiberMonitor extends ChangeNotifier {
  FiberMonitor._(this.device) : profile = OltProfile.fromDevice(device);

  static final Map<int, FiberMonitor> _all = {};

  /// للاختبار: مصدرٌ وساعة بديلان.
  static FiberBackend backend = const FiberBackend();
  static DateTime Function() clock = DateTime.now;

  static FiberMonitor of(NetworkDevice d) {
    final m = _all.putIfAbsent(d.id, () => FiberMonitor._(d));
    m.device = d;
    return m;
  }

  static FiberMonitor? existing(int deviceId) => _all[deviceId];
  static Iterable<FiberMonitor> get all => _all.values;

  /// من [SessionManager] عند الخروج: تتوقّف كلّها ولا يرث أحدٌ قراءات سابقه.
  static void resetAll() {
    for (final m in _all.values) {
      m._stop();
      m._users = 0;
      m._bgUsers = 0;
    }
    _all.clear();
  }

  static const _structureEvery = Duration(seconds: 15);
  static const _bgStructureEvery = Duration(seconds: 30);
  static const _opticsEvery = Duration(seconds: 60);
  static const _bgOpticsEvery = Duration(minutes: 2);
  static const _namesEvery = Duration(minutes: 10);
  static const _devicesEvery = Duration(minutes: 5);
  static const _rxUploadEvery = Duration(minutes: 10);

  NetworkDevice device;
  OltProfile profile;

  VsolOltStats? stats;
  DateTime? statsAt;
  final Map<String, VsolTraffic> ponRates = {};
  List<FiberOnuLive> onus = const [];
  List<FiberOutage> outages = const [];
  FiberOltCaps? caps;
  String? error;
  bool busy = false;
  DateTime? lastOkAt;

  /// شاشة الربط/التشخيص تطلب الأجهزة خلف كلّ ONU (ثقيلة — لا تُقرأ بلا طلب).
  bool wantDevices = false;

  /// آخر الأجهزة التي فُتحت بوضع الفنّي (الأحدث أوّلاً) — اختصارٌ للفنّي بالموقع، يزول مع الجلسة.
  final List<String> techRecent = [];

  final Map<int, BdcomOnuReading> _optics = {};
  DateTime? _opticsAt;
  final Map<int, FiberDropReason> _reasons = {};
  final Map<int, DateTime> _changes = {};
  final Map<int, String> _names = {};
  DateTime? _namesAt;
  OltEponDetails _epon = const OltEponDetails();
  VsolGponSnapshot? _gpon;
  DateTime? _gponAt, _devicesAt;
  final Map<String, bool> _wasOnline = {};
  bool _first = true;
  DateTime? _rxUploadAt;
  bool _capsDone = false;

  /// الأعطال المبلَّغة: مكانها ← سجلّها على الخادم (أو محلّيّ بلا رقم).
  final Map<String, ({FiberEventRecord? record, Set<String> keys, DateTime startedAt})> _open = {};

  int _users = 0;
  int _bgUsers = 0;
  Timer? _timer;
  Duration _cost = Duration.zero;

  bool get running => _users > 0 || _bgUsers > 0;
  bool get background => _users == 0 && _bgUsers > 0;
  int get oltId => device.id;
  FiberOltSettings get settings => FiberStore.layout.value.settingsOf(oltId);

  void acquire({bool background = false}) {
    final was = running;
    if (background) {
      _bgUsers++;
    } else {
      _users++;
    }
    if (!was) {
      _seed();
      _schedule(Duration.zero);
    } else if (!background && _users == 1) {
      // شاشةٌ فُتحت على مراقبٍ خلفيّ: قراءةٌ فوريّة بإيقاع الشاشة.
      _schedule(Duration.zero);
    }
  }

  void release({bool background = false}) {
    if (background) {
      if (_bgUsers > 0) _bgUsers--;
    } else {
      if (_users > 0) _users--;
    }
    if (!running) _stop();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    if (!running) return;
    _timer = Timer(d, () async {
      await tick();
      if (!running) return;
      final base = background ? _bgStructureEvery : _structureEvery;
      final paced = _cost * 2;
      _schedule(paced > base ? paced : base);
    });
  }

  /// بذرةٌ من لوحة الأولت إن قرأته قبل دقائق — الشاشة لا تبدأ فارغة.
  void _seed() {
    if (stats != null) return;
    final s = DeviceStatsCache.instance.seedFor<VsolOltStats>(device.id);
    if (s == null || s.isEmpty) return;
    stats = s;
    statsAt = clock();
    if (s.profile.identified) profile = s.profile;
    _rebuild();
  }

  /// قراءةٌ الآن (زرّ التحديث، أو أوّل فتح).
  Future<void> refreshNow() => tick(force: true);

  @visibleForTesting
  Future<void> tick({bool force = false}) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    final clockStart = DateTime.now();
    try {
      final community = await backend.community(device);
      if (community == null) {
        error = 'أدخل الـcommunity من إعدادات الجهاز';
        return;
      }
      final snmp = backend.snmp(device, community);
      final now = clock();

      // ١. البنية (الحالة) + عدّادات المنافذ.
      var s = await backend.structure(device, community, profile);
      if (s.profile.identified) profile = s.profile;
      if (s.isEmpty) {
        error = 'الأولت لم يُجب بجدوله كاملاً — نعيد بعد قليل';
        return;
      }
      final prev = stats;
      final prevAt = statsAt;
      try {
        s = await backend.hot(device, community, s);
      } catch (_) {/* بلا عدّادات هذه المرّة */}
      if (prev != null && prevAt != null && prev.hasCounters && s.hasCounters) {
        final fresh = VsolTraffic.between(prev, s, now.difference(prevAt));
        for (final p in s.ponPorts) {
          final v = fresh[p.label];
          if (v != null && v.known) ponRates[p.label] = v;
        }
      }

      // ٢. التغيّرات: لحظتها وسببها.
      final changed = <VsolOnu>[];
      final offlineNow = <VsolOnu>[];
      for (final o in s.onus) {
        final was = _wasOnline[o.label];
        if (was != null && was != o.online) changed.add(o);
        if (!o.online) offlineNow.add(o);
      }
      final targets = _first ? s.onus : changed;
      if (targets.isNotEmpty) {
        final ch = await OltFiberReads.lastChanges(snmp, targets.map((o) => o.ifIndex), now: now);
        for (final o in targets) {
          final t = ch[o.ifIndex];
          if (t != null) {
            _changes[o.ifIndex] = t;
          } else if (!_first && changed.contains(o)) {
            // الأولت لا يعطي اللحظة: لحظة رصدنا (دقّة الإيقاع) — فتتجمّع أجهزة الدورة الواحدة عطلاً واحداً.
            _changes[o.ifIndex] = now;
          }
        }
      }
      final reasonTargets = _first ? offlineNow : [for (final o in changed) if (!o.online) o];
      if (reasonTargets.isNotEmpty) {
        _reasons.addAll(await OltFiberReads.dropReasons(snmp, profile, reasonTargets));
      }
      for (final o in changed) {
        if (o.online) _reasons.remove(o.ifIndex);
      }
      for (final o in s.onus) {
        _wasOnline[o.label] = o.online;
      }
      _first = false;

      // ٣. الضوء.
      final opticsEvery = background ? _bgOpticsEvery : _opticsEvery;
      if (force || _opticsAt == null || now.difference(_opticsAt!) >= opticsEvery) {
        final online = s.onus.where((o) => o.online).toList();
        Map<int, BdcomOnuReading> r = const {};
        if (profile.readsBdcomEponTables) {
          r = await BdcomEpon.readings(snmp, online.where((o) => o.technology == VsolPonTechnology.epon).map((o) => o.ifIndex));
        } else if (profile.readsVsolTables) {
          r = await OltFiberReads.vsolOptics(snmp, online);
        }
        _optics
          ..clear()
          ..addAll(r);
        _opticsAt = now;
        final book = await FiberStore.loadBook(oltId, now: now);
        for (final o in online) {
          final rx = r[o.ifIndex]?.rxDbm;
          if (FiberBands.plausible(rx)) book.record(o.label, rx!, now);
        }
      }

      // ٤. الأسماء (بطيئة التغيّر).
      if (_namesAt == null || now.difference(_namesAt!) >= _namesEvery) {
        _names
          ..clear()
          ..addAll(await OltFiberReads.names(snmp, profile, s.onus));
        _namesAt = now;
      }

      // ٥. الأجهزة خلف كلّ ONU (للربط) — بطلب.
      if (wantDevices && (force || _devicesAt == null || now.difference(_devicesAt!) >= _devicesEvery)) {
        await _readDevices(snmp, s);
        _devicesAt = now;
      }

      stats = s;
      statsAt = now;
      lastOkAt = now;
      error = null;
      _rebuild();

      // ٦. الأعطال.
      await _syncOutages(now);

      // ٧. القدرات مرّةً بالجلسة، والضوء للخادم كلّ عشر دقائق.
      if (!_capsDone) {
        _capsDone = true;
        unawaited(_probeCaps(snmp, s, now));
      }
      if (_rxUploadAt == null || now.difference(_rxUploadAt!) >= _rxUploadEvery) {
        _rxUploadAt = now;
        unawaited(_uploadRx(now));
      }
    } on VsolException catch (e) {
      error = e.message;
    } on SnmpException catch (e) {
      error = 'تعذّر الاتّصال بالأولت: $e';
    } catch (e) {
      error = 'تعذّرت القراءة: $e';
    } finally {
      _cost = DateTime.now().difference(clockStart);
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _readDevices(SnmpV2c snmp, VsolOltStats s) async {
    final epon = s.onus.where((o) => o.technology == VsolPonTechnology.epon).toList();
    if (epon.isNotEmpty && profile.vendor != OltVendor.unknown) {
      final known = {for (final o in epon) o.ifIndex};
      var next = _epon;
      if (profile.readsBdcomEponTables) {
        final macs = await BdcomEpon.onuMacs(snmp, known);
        next = next.copyWith(onuMacs: {...next.onuMacs, ...macs}, macsAt: clock());
      }
      final f = await BridgeFdb.fetch(snmp, targets: known);
      final keep = !f.complete && _epon.fdb.complete && f.supported;
      next = keep ? next.copyWith(fdbAt: _epon.fdbAt) : next.copyWith(fdb: f, fdbAt: clock());
      _epon = next;
    }
    if (profile.readsVsolTables && s.onus.any((o) => o.technology == VsolPonTechnology.gpon)) {
      _gpon = await VsolGponDetails.fetch(snmp);
      _gponAt = clock();
    }
  }

  /// يدمج القراءات كلّها فوق آخر بنية.
  void _rebuild() {
    final s = stats;
    if (s == null) return;
    var merged = s.withEponDetails(_epon);
    final g = _gpon;
    if (g != null && _gponAt != null) merged = merged.withGponDetails(g, _gponAt!);
    onus = List.unmodifiable([
      for (final o in merged.onus)
        FiberOnuLive(
          onu: _withNameAndOptics(o),
          reason: o.online ? null : _reasons[o.ifIndex],
          changedAt: _changes[o.ifIndex],
        ),
    ]);
  }

  VsolOnu _withNameAndOptics(VsolOnu o) {
    final r = o.online ? _optics[o.ifIndex] : null;
    final name = _names[o.ifIndex];
    if (r == null && (name == null || (o.name?.isNotEmpty ?? false))) return o;
    return VsolOnu(
      ifIndex: o.ifIndex,
      slot: o.slot,
      ponPort: o.ponPort,
      onuId: o.onuId,
      online: o.online,
      mac: o.mac,
      technology: o.technology,
      name: (o.name?.isNotEmpty ?? false) ? o.name : name,
      serial: o.serial,
      learnedMacs: o.learnedMacs,
      learnedMacsReadAt: o.learnedMacsReadAt,
      learnedMacsComplete: o.learnedMacsComplete,
      speedMbps: o.speedMbps,
      rxBytes: o.rxBytes,
      txBytes: o.txBytes,
      reading: r ?? o.reading,
      readingAt: r != null ? _opticsAt : o.readingAt,
      vendor: o.vendor,
      module: o.module,
    );
  }

  // ── الأعطال ───────────────────────────────────────────────────────────────────────────

  Future<void> _syncOutages(DateTime now) async {
    final layout = FiberStore.layout.value;
    final found = FiberOutageDetector.detect(oltId: oltId, layout: layout, onus: onus, now: now);
    outages = List.unmodifiable(found);
    final online = {for (final o in onus) o.key: o.online};

    // جديد ⇒ تبليغ الخادم (يدمجه مع ما رآه جهازٌ آخر، ويُشعر).
    for (final e in found) {
      if (_open.containsKey(e.scopeKey)) {
        final cur = _open[e.scopeKey]!;
        _open[e.scopeKey] = (record: cur.record, keys: {...cur.keys, ...e.onuKeys}, startedAt: cur.startedAt);
        continue;
      }
      final started = e.startedAt ?? now;
      _open[e.scopeKey] = (record: null, keys: e.onuKeys.toSet(), startedAt: started);
      final text = FiberText.outagePush(e, layout, device.name);
      final r = await FiberApi.reportEvent(
        oltId: oltId,
        kind: e.kind.name,
        scope: e.scope.name,
        scopeKey: e.scopeKey,
        pon: e.pon,
        // صندوقٌ لم يصل الخادم بعد (رقمٌ سالب، على الجهاز وحده) لا يُرسل رقمه — الخادم يرفضه.
        boxId: (e.boxId ?? 0) > 0 ? e.boxId : null,
        onus: e.onuKeys,
        startedAt: started,
        title: text.title,
        body: text.body,
      );
      if (r.event != null) {
        _open[e.scopeKey] = (record: r.event, keys: e.onuKeys.toSet(), startedAt: started);
        FiberStore.applyEvent(r.event!);
      }
    }

    // انتهى ⇒ رجع ٨٠٪ من أجهزته.
    final ended = <String>[];
    for (final entry in _open.entries) {
      final keys = entry.value.keys;
      if (keys.isEmpty) continue;
      final back = keys.where((k) => online[k] == true).length;
      final stillDetected = found.any((f) => f.scopeKey == entry.key);
      if (!stillDetected && back >= (keys.length * 0.8).ceil()) ended.add(entry.key);
    }
    for (final k in ended) {
      final cur = _open.remove(k)!;
      final rec = cur.record;
      if (rec == null) continue;
      final text = FiberText.backPush(rec, layout, device.name);
      final r = await FiberApi.endEvent(rec.id, now, title: text.title, body: text.body);
      final done = r.event ?? rec.copyWith(endedAt: now);
      FiberStore.applyEvent(done);
      if (done.autoBack && done.backSentAt == null) await _sendBack(done);
    }
  }

  /// «رجع النت» للمشتركين المربوطين بأجهزة العطل — مرّةً واحدة بين كلّ الأجهزة (الخادم يحجز الإرسال لأوّل من يطلبه).
  Future<void> _sendBack(FiberEventRecord e) async {
    final users = FiberText.linkedUsers(FiberStore.layout.value, oltId, e.onuKeys, onus);
    if (users.isEmpty) return;
    if (!await FiberApi.claimBack(e.id)) return;
    await BroadcastApi.broadcast(intent: MessageIntent.general, message: settings.backMessage, targetUsernames: users);
  }

  Future<void> _probeCaps(SnmpV2c snmp, VsolOltStats s, DateTime now) async {
    try {
      final c = await OltFiberReads.probe(snmp, profile, s.onus, now: now);
      caps = c;
      final js = c.toJson();
      FiberStore.applyCaps(oltId, js);
      await FiberApi.reportCaps(oltId, js);
      notifyListeners();
    } catch (_) {/* أفضل جهد */}
  }

  Future<void> _uploadRx(DateTime now) async {
    final book = FiberStore.bookOf(oltId);
    await FiberStore.persistBook(oltId, now: now);
    if (!FiberStore.serverReady || !book.hasDirty) return;
    final rows = book.takeDirty();
    if (!await FiberApi.uploadRx(oltId, rows)) book.restoreDirty(rows);
  }

  /// ONU واحدة حيّة الآن — قراءة الضوء وحدها بلا مسح.
  Future<BdcomOnuReading?> readOne(VsolOnu o) async {
    final community = await backend.community(device);
    if (community == null || !o.online) return null;
    return _readOptics(backend.snmp(device, community), o);
  }

  /// وضع الفنّي كلّ ثانيتين: حالة ONU واحدة من ifOperStatus (مصدر المسح نفسه) ثمّ ضوؤها إن كانت متّصلة — فيظهر
  /// رجوعها بعد التنظيف خلال ثانيتين لا بعد دورة المسح. `online: null` = الأولت لم يُجب.
  Future<({bool? online, BdcomOnuReading? reading})> probeOne(VsolOnu o) async {
    final community = await backend.community(device);
    if (community == null) return (online: null, reading: null);
    final snmp = backend.snmp(device, community);
    bool? up;
    try {
      final vb = await snmp.get(['${OltFiberReads.ifOperStatusOid}.${o.ifIndex}']);
      final v = vb.isEmpty ? null : vb.first.asIntOrNull;
      if (v != null) up = v == 1;
    } catch (_) {/* لا جواب — نجرّب الضوء على آخر حالةٍ معروفة */}
    if (up == false || (up == null && !o.online)) return (online: up, reading: null);
    final reading = await _readOptics(snmp, o.online ? o : o.copyWith(online: true));
    return (online: up ?? (reading != null ? true : null), reading: reading);
  }

  /// «التقط بالفصل» (وضع الفنّي): الفنّي يفصل ليف الجهاز اللي قدّامه فنعرفه بلا كتابة. عمود الحالة وحده (ifOperStatus —
  /// مصدر المسح نفسه، GETBULK خفيف) كلّ [every] حتى [window]، ويُقارن بأوّل قراءة: أوّل دورةٍ تغيّر فيها جهاز (انفصل،
  /// أو اختفى صفّه، أو رجع) تُرجع أجهزتها — أكثر من واحد بنفس اللحظة = عطل، والشاشة تخيّر. فارغ = لم يتغيّر شيء أو أُلغي.
  Future<List<({VsolOnu onu, bool nowOnline})>> catchChange({
    Duration window = const Duration(seconds: 90),
    Duration every = const Duration(seconds: 2),
    bool Function()? cancelled,
    void Function(int watched)? onStart,
  }) async {
    final s = stats;
    if (s == null || s.onus.isEmpty) return const [];
    final community = await backend.community(device);
    if (community == null) return const [];
    final snmp = backend.snmp(device, community);
    final byIf = {for (final o in s.onus) o.ifIndex: o};
    const base = OltFiberReads.ifOperStatusOid;
    Future<Map<int, bool>?> read() async {
      try {
        final rows = await snmp.walk(base, chunkSize: 50, maxIterations: 60);
        final out = <int, bool>{};
        for (final vb in rows) {
          if (!vb.oid.startsWith('$base.')) continue;
          final i = int.tryParse(vb.oid.substring(base.length + 1));
          final v = vb.asIntOrNull;
          if (i != null && v != null && byIf.containsKey(i)) out[i] = v == 1;
        }
        return out.isEmpty ? null : out;
      } catch (_) {
        return null;
      }
    }

    Map<int, bool>? first;
    final end = clock().add(window);
    while (clock().isBefore(end)) {
      if (cancelled?.call() == true) return const [];
      final now = await read();
      if (cancelled?.call() == true) return const [];
      if (now != null) {
        if (first == null) {
          first = now;
          onStart?.call(now.length);
        } else {
          final changed = [
            for (final e in first.entries)
              if ((now[e.key] ?? false) != e.value) (onu: byIf[e.key]!, nowOnline: now[e.key] ?? false),
          ];
          if (changed.isNotEmpty) {
            unawaited(refreshNow()); // المسح يلحق: لحظة السقوط وسببه
            return changed;
          }
        }
      }
      await Future<void>.delayed(every);
    }
    return const [];
  }

  Future<BdcomOnuReading?> _readOptics(SnmpV2c snmp, VsolOnu o) async {
    final Map<int, BdcomOnuReading> r = profile.readsBdcomEponTables
        ? await BdcomEpon.readings(snmp, [o.ifIndex])
        : await OltFiberReads.vsolOptics(snmp, [o]);
    final reading = r[o.ifIndex];
    if (reading != null) {
      _optics[o.ifIndex] = reading;
      final rx = reading.rxDbm;
      if (FiberBands.plausible(rx)) FiberStore.bookOf(oltId).record(o.label, rx!, clock());
      _rebuild();
      notifyListeners();
    }
    return reading;
  }

  @visibleForTesting
  static void debugReset() {
    resetAll();
    backend = const FiberBackend();
    clock = DateTime.now;
  }
}
