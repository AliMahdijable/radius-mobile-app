// «الفحص الشامل» — الجلب: من شبكتك (بنك ثلاث حزم + قراءة الجهاز المفصّلة) أو عبر الـVPN («ويخضع لل vpn» — المالك ٦ نوفمبر).
// المقيِّم النقيّ في devices_check.dart؛ هنا الشبكة والتقدّم ولقطة الفحص السابق.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/agent_alerts_api.dart';
import '../api/big_subscribers_api.dart';
import '../api/subscribers_api.dart';
import '../models/subscriber.dart';
import '../api/network_devices_api.dart';
import '../models/network_device.dart';
import '../screens/network_devices/device_vitals.dart';
import 'connection_alerts.dart';
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

  Future<void> run() async {
    if (running) return;
    final gen = ++_gen;
    running = true;
    done = 0;
    error = null;
    errorReason = null;
    line = null;
    reports.clear();
    notifyListeners();
    try {
      final (limits, memos, macs) = await (loadLimits(), DevicesCheckMemoStore.load(), _macIndex()).wait;
      if (gen != _gen) return;
      if (viaVpn) {
        await _viaVpn(limits, memos, macs, gen);
      } else {
        await _local(limits, memos, macs, gen);
      }
      if (gen != _gen) return;
      at = DateTime.now();
      await DevicesCheckMemoStore.save({
        for (final r in reports.values)
          if (r.memo != null) r.device.id: r.memo!,
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

  @override
  void dispose() {
    _gen++;
    super.dispose();
  }

  // ── من شبكتك ──────────────────────────────────────────────────────

  Future<void> _local(CheckLimits limits, Map<int, CheckMemo> memos, Map<String, String> macs, int gen) async {
    final queue = Queue<NetworkDevice>.from(devices);
    Future<void> worker() async {
      while (queue.isNotEmpty && gen == _gen) {
        final d = queue.removeFirst();
        final r = await _checkLocal(d, limits, memos[d.id], macs);
        if (gen != _gen) return;
        reports[d.id] = r;
        done++;
        notifyListeners();
      }
    }

    // ستّةٌ معاً: القراءة المفصّلة تفتح جلسة إدارةٍ على الجهاز — لا نغرق الشبكة ولا الأجهزة الضعيفة، والنتائج تظهر أوّلاً بأوّل
    await Future.wait([for (var i = 0; i < 6; i++) worker()]);
  }

  static Future<DeviceCheckReport> _checkLocal(NetworkDevice d, CheckLimits limits, CheckMemo? prev, Map<String, String> macs) async {
    DeviceProbe? probe;
    try {
      probe = await (debugProbe?.call(d) ?? NetworkDevicesApi.probeDevice(d, ping: true)).timeout(const Duration(seconds: 15));
    } catch (_) {}
    final alive = switch (probe?.status) { 'online' => true, 'offline' => false, _ => null };
    if (alive == false) return DevicesCheck.evaluate(d: d, alive: false, limits: limits, prev: prev);

    // ما يمنع القراءة (بلا بيانات دخول، علامةٌ بلا مقاييس، بروتوكولٌ لا يُقرأ) — «غير متّصل/خارج شبكتك» حسمهما البنك أعلاه
    final skip = DeviceVitals.skipReason(d);
    final hard = skip == null || skip == DeviceVitals.offNetworkReason || skip == 'غير متّصل' ? null : skip;
    if (hard != null) {
      return DevicesCheck.evaluate(
          d: d, alive: alive, ms: probe?.responseMs, loss: probe?.packetLoss, unreadReason: '$hard — الحال فقط', limits: limits, prev: prev);
    }
    try {
      final p = await (debugFetch?.call(d) ?? DeviceVitals.fetch(d, detailed: true)).timeout(const Duration(seconds: 25));
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
      );
    } catch (_) {
      final svc = probe?.serviceOk == false;
      return DevicesCheck.evaluate(
        d: d,
        alive: alive ?? true,
        ms: probe?.responseMs,
        loss: probe?.packetLoss,
        unreadReason: svc
            ? 'يردّ، لكن خدمة الإدارة لا تجيب — تأكّد من المنفذ والبروتوكول'
            : 'يردّ، لكن ما انقرت معلوماته — تأكّد من اسم المستخدم والرمز',
        limits: limits,
        prev: prev,
      );
    }
  }

  // ── عبر الـVPN ──────────────────────────────────────────────────────

  Future<void> _viaVpn(CheckLimits limits, Map<int, CheckMemo> memos, Map<String, String> macs, int gen) async {
    final job = VpnNow.devices;
    void onJob() {
      line = job.line;
      notifyListeners();
    }

    job.addListener(onJob);
    try {
      if (job.busy) {
        // فحصٌ جارٍ (وضع VPN) — ننتظره لا نبدأ ثانياً
        final c = Completer<void>();
        void wait() {
          if (!job.busy && !c.isCompleted) c.complete();
        }

        job.addListener(wait);
        await c.future.timeout(const Duration(minutes: 4), onTimeout: () {});
        job.removeListener(wait);
      } else {
        await job.run();
      }
    } finally {
      job.removeListener(onJob);
    }
    if (gen != _gen) return;
    if (job.phase == VpnBarPhase.failed || job.result == null) {
      error = job.line ?? 'تعذّر الفحص عبر الـVPN';
      errorReason = job.reason;
      return;
    }
    for (final d in devices) {
      final r = VpnNow.deviceFor(d.id);
      final prev = memos[d.id];
      if (r == null) {
        reports[d.id] = DevicesCheck.evaluate(
            d: d, alive: null, unreadReason: 'لم يشمله الفحص عبر الـVPN — عنوانه خارج طريق الشركة', limits: limits, prev: prev, viaVpn: true);
      } else {
        final v = r.vitals;
        final st = v == null ? null : DeviceVitals.fromVpn(v);
        reports[d.id] = DevicesCheck.evaluate(
          d: d,
          alive: r.alive,
          ms: r.ms,
          detail: st?.detail,
          unreadReason: r.alive && st == null ? 'يردّ عبر الـVPN — معلوماته لا تُقرأ عن بُعد لهذا النوع' : null,
          limits: limits,
          prev: prev,
          viaVpn: true,
          portsCountsOnly: v?['pl'] is! List,
          macUsers: macs,
        );
      }
      done++;
    }
    notifyListeners();
  }
}
