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
import '../core/net/device_net.dart';
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
        await DeviceNet.vpn(() => _local(limits, memos, macs, gen));
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
    // عبر الـVPN كلّ رحلةٍ أطول (الموبايل ⇄ الخادم ⇄ النفق) ⇒ مهلٌ أوسع
    final piped = DeviceNet.viaPipe(d.ip);
    try {
      probe = await (debugProbe?.call(d) ?? NetworkDevicesApi.probeDevice(d, ping: true)).timeout(Duration(seconds: piped ? 25 : 15));
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
      final p = await (debugFetch?.call(d) ?? DeviceVitals.fetch(d, detailed: true)).timeout(Duration(seconds: piped ? 45 : 25));
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
}
