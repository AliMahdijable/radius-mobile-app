// «الفحص الشامل» في «كل الشركات» (٧ نوفمبر — المالك: «دمج الأجهزة والفحص الشامل… في كل الشركات»، و«تنبيه الوكيل باسم الشركة
// إذا احتاج فحصها إلى VPN ولم يتوفر طريق لها»). أجهزة الشركة المفتوحة بفحصها المعتاد (من شبكتك، أو عبر ممرّ الـVPN)، وأجهزة كلّ
// شركةٍ أخرى بفحص الخادم عبر نفق تلك الشركة — طلباتٌ موجَّهة بمفتاحها (companyRoutingAllow: الطريق، الحدود، بدء الفحص ونتيجته)؛
// كلمات سرّ أجهزتها لا تصل الهاتف أبداً. شركةٌ بلا طريق VPN تُسمّى ولا تُعدّ أجهزتها طافية.
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/agent_alerts_api.dart';
import '../api/api_client.dart';
import '../api/company_route.dart';
import '../api/vpn_now_api.dart';
import '../models/merged_company.dart';
import '../models/network_device.dart';
import '../models/subscriber.dart';
import '../screens/network_devices/device_vitals.dart';
import 'connection_alerts.dart';
import 'devices_check.dart';
import 'devices_check_runner.dart';
import 'merged_mode.dart';

/// شركةٌ في نطاق الفحص وأجهزتها. [open]: الشركة المفتوحة (فحصها المعتاد).
class MergedCheckPart {
  const MergedCheckPart({required this.company, required this.devices, this.open = false});
  final MergedCompany company;
  final List<NetworkDevice> devices;
  final bool open;
}

enum MergedCheckStatus { waiting, running, done, noVpn, failed }

/// حال شركةٍ في الفحص — سطرها في بطاقة «الشركات».
class MergedCheckCompanyState {
  MergedCheckCompanyState(this.part);
  final MergedCheckPart part;
  MergedCheckStatus status = MergedCheckStatus.waiting;

  /// سطرها بعد الفحص (السبب حين لم يكتمل).
  String? message;

  /// فُحصت عبر الـVPN (شركةٌ أخرى دائماً؛ والمفتوحة بوضعه أو خارج شبكتها).
  bool viaVpn = false;

  /// حدودها الافتراضيّة (تعذّرت قراءة إعداداتها).
  bool defaultLimits = false;
}

/// نتيجة سؤال الطريق: مربوطة / بلا VPN / تعذّر السؤال.
enum MergedVpnRoute { linked, missing, unknown }

class MergedDevicesCheckRunner extends DevicesCheckRunner {
  MergedDevicesCheckRunner(this.parts, {required bool openViaVpn, this.openOffNetwork = false})
      : _openViaVpn = openViaVpn,
        super([for (final p in parts) ...p.devices], viaVpn: openViaVpn);

  final List<MergedCheckPart> parts;
  final bool _openViaVpn;

  /// الشركة المفتوحة خارج شبكتها بلا طريق VPN — لا تُفحص (المحلّيّ سيقول «طافي» كذباً)، وسطرها يقول لماذا.
  final bool openOffNetwork;

  late final Map<String, MergedCheckCompanyState> states = {for (final p in parts) p.company.key: MergedCheckCompanyState(p)};

  /// شركة كلّ جهاز: المعرّف ⇒ مفتاحها.
  late final Map<int, String> companyOf = {
    for (final p in parts)
      for (final d in p.devices) d.id: p.company.key,
  };

  /// مشتركو كلّ شركةٍ أخرى بيوزرهم (لفتح صفحة المشترك من صفّ محطّةٍ/ONU — موجَّهةً لشركته).
  final _remoteSubs = <String, Map<String, Subscriber>>{};
  DevicesCheckRunner? _inner;

  // ── للاختبار: بدائل الشبكة لكلّ شركة (داخل نطاقها الموجَّه) ──
  @visibleForTesting
  static Future<MergedVpnRoute> Function(MergedCompany c)? debugRoute;
  @visibleForTesting
  static Future<({String? id, String? error})> Function(MergedCompany c)? debugStart;
  @visibleForTesting
  static Future<({bool done, VpnNowProgress? progress, VpnNowResult? result})?> Function(MergedCompany c, String id)? debugPoll;
  @visibleForTesting
  static Future<({CheckLimits limits, bool complete})> Function(MergedCompany c)? debugLimits;
  @visibleForTesting
  static Future<List<Subscriber>?> Function(MergedCompany c)? debugSubscribers;
  @visibleForTesting
  static Duration pollEvery = const Duration(seconds: 2);
  static const maxWait = Duration(minutes: 6);

  int _gen = 0;

  @override
  bool isRemote(int deviceId) {
    final key = companyOf[deviceId];
    return key != null && !(states[key]?.part.open ?? false);
  }

  @override
  Subscriber? subscriberOn(int deviceId, String user) {
    final key = companyOf[deviceId];
    if (key == null) return null;
    if (states[key]?.part.open ?? false) return _inner?.subscriberFor(user);
    return _remoteSubs[key]?[user];
  }

  @override
  Future<void> run() async {
    if (running) return;
    final gen = ++_gen;
    running = true;
    done = 0;
    error = null;
    errorReason = null;
    line = null;
    reports.clear();
    _remoteSubs.clear();
    for (final s in states.values) {
      s
        ..status = MergedCheckStatus.waiting
        ..message = null
        ..viaVpn = !s.part.open
        ..defaultLimits = false;
    }
    notifyListeners();
    try {
      final memos = await DevicesCheckMemoStore.load();
      if (gen != _gen) return;
      final remote = [for (final p in parts) if (!p.open && p.devices.isNotEmpty) p];
      await Future.wait([
        _openPart(gen),
        () async {
          // واحدةً بعد واحدة: كلّ فحصٍ نفقُ شركةٍ على الخادم — لا نفتح أنفاق الشركات كلّها معاً
          for (final p in remote) {
            if (gen != _gen) return;
            await _remotePart(p, memos, gen);
          }
        }(),
      ]);
      if (gen != _gen) return;
      at = DateTime.now();
      final remoteMemos = {
        for (final r in reports.values)
          if (r.memo != null && isRemote(r.device.id)) r.device.id: r.memo!,
      };
      if (remoteMemos.isNotEmpty) await DevicesCheckMemoStore.save(remoteMemos);
    } catch (_) {
      error ??= 'تعذّر إكمال الفحص';
    } finally {
      if (gen == _gen) {
        running = false;
        line = null;
        notifyListeners();
      }
    }
  }

  /// الشركة المفتوحة: الفحص المعتاد نفسه (DevicesCheckRunner) — تقاريره تُنقل هنا أوّلاً بأوّل.
  Future<void> _openPart(int gen) async {
    final open = parts.where((p) => p.open && p.devices.isNotEmpty).firstOrNull;
    if (open == null) return;
    final st = states[open.company.key]!..viaVpn = _openViaVpn;
    if (openOffNetwork) {
      st
        ..status = MergedCheckStatus.noVpn
        ..message = 'خارج شبكتك — اربط لها VPN من «المزيد» حتى تُفحص أجهزتها عن بُعد';
      notifyListeners();
      return;
    }
    st.status = MergedCheckStatus.running;
    final inner = DevicesCheckRunner(open.devices, viaVpn: _openViaVpn);
    _inner?.dispose();
    _inner = inner;
    void sync() {
      if (gen != _gen) return;
      for (final e in inner.reports.entries) {
        if (!reports.containsKey(e.key)) {
          reports[e.key] = e.value;
          done++;
        }
      }
      notifyListeners();
    }

    inner.addListener(sync);
    try {
      await inner.run();
    } finally {
      inner.removeListener(sync);
    }
    if (gen != _gen) return;
    sync();
    if (inner.error != null) {
      st
        ..status = MergedCheckStatus.failed
        ..message = inner.error;
    } else {
      st.status = MergedCheckStatus.done;
    }
    notifyListeners();
  }

  /// شركةٌ أخرى: طريقها ⇒ حدودها ومشتركوها ⇒ فحص الخادم عبر نفقها ⇒ تقرير كلّ جهاز بقاعدة الفحص نفسها.
  Future<void> _remotePart(MergedCheckPart p, Map<int, CheckMemo> memos, int gen) async {
    final c = p.company;
    final st = states[c.key]!..status = MergedCheckStatus.running;
    line = 'يفحص «${c.name}» عبر الـVPN…';
    notifyListeners();
    void fail(MergedCheckStatus s, String msg) {
      st
        ..status = s
        ..message = msg;
    }

    await CompanyRoute.run(c.key, () async {
      final route = await (debugRoute?.call(c) ?? _route());
      if (gen != _gen) return;
      if (route == MergedVpnRoute.missing) {
        return fail(MergedCheckStatus.noVpn, 'تحتاج VPN للفحص الشامل — افتحها واربط VPN من «المزيد»');
      }
      if (route == MergedVpnRoute.unknown) {
        return fail(MergedCheckStatus.failed, 'تعذّر التحقّق من طريق الـVPN — حاول بعد قليل');
      }
      final (lim, subs) = await (
        debugLimits?.call(c) ?? _limits(),
        debugSubscribers?.call(c) ?? _subscribers(c),
      ).wait;
      if (gen != _gen) return;
      st.defaultLimits = !lim.complete;
      final macs = <String, String>{};
      final byUser = <String, Subscriber>{};
      for (final s in subs ?? const <Subscriber>[]) {
        final sub = s.companyKey == c.key ? s : s.withCompany(c.key);
        byUser[sub.username] = sub;
        final m = DevicesCheck.normMac(sub.lastMac);
        if (m != null) macs[m] = sub.username;
      }
      _remoteSubs[c.key] = byUser;

      final start = await (debugStart?.call(c) ?? VpnNowApi.start(VpnNowKind.devices));
      if (gen != _gen) return;
      final id = start.id;
      if (id == null) return fail(MergedCheckStatus.failed, start.error ?? 'تعذّر بدء الفحص — حاول بعد قليل');
      final clock = Stopwatch()..start();
      var misses = 0;
      VpnNowResult? result;
      while (gen == _gen && clock.elapsed < maxWait) {
        await Future<void>.delayed(pollEvery);
        if (gen != _gen) return;
        final polled = await (debugPoll?.call(c, id) ?? VpnNowApi.poll(id));
        if (polled == null) {
          if (++misses >= 6) return fail(MergedCheckStatus.failed, 'انقطع الاتصال بالخادم أثناء الفحص');
          continue;
        }
        misses = 0;
        final pr = polled.progress;
        if (pr != null && pr.total > 0) {
          line = 'يفحص «${c.name}» عبر الـVPN… ${pr.done} من ${pr.total}';
          notifyListeners();
        }
        if (polled.done) {
          result = polled.result ?? const VpnNowResult(ok: false, message: 'تعذّر قراءة نتيجة الفحص');
          break;
        }
      }
      if (gen != _gen) return;
      if (result == null) return fail(MergedCheckStatus.failed, 'انتهت مهلة الفحص — أعد المحاولة');
      if (!result.ok) return fail(MergedCheckStatus.failed, result.message);
      final byId = {for (final d in result.devices) d.id: d};
      for (final d in p.devices) {
        reports[d.id] = remoteReport(d, byId[d.id], lim.limits, memos[d.id], macs);
        done++;
      }
      st.status = MergedCheckStatus.done;
    });
    notifyListeners();
  }

  /// تقرير جهاز شركةٍ أخرى من فحص الخادم — كما كان «الفحص الشامل» عبر الـVPN قبل الممرّ (d6524c20): الجهاز الغائب عن النتيجة
  /// «لم يُقرأ» لا «طافي»، والمعلومات ما قرأه الخادم.
  @visibleForTesting
  static DeviceCheckReport remoteReport(
      NetworkDevice d, VpnDeviceResult? r, CheckLimits limits, CheckMemo? prev, Map<String, String> macs) {
    if (r == null) {
      return DevicesCheck.evaluate(
          d: d, alive: null, unreadReason: 'لم يشمله الفحص عبر الـVPN — عنوانه خارج طريق الشركة', limits: limits, prev: prev, viaVpn: true);
    }
    final v = r.vitals;
    final st = v == null ? null : DeviceVitals.fromVpn(v);
    return DevicesCheck.evaluate(
      d: d,
      alive: r.alive,
      ms: r.ms,
      detail: st?.detail,
      unreadReason: r.alive && st == null ? 'يردّ عبر الـVPN — معلوماته ما انقرت عن بُعد' : null,
      limits: limits,
      prev: prev,
      viaVpn: true,
      portsCountsOnly: v?['pl'] is! List,
      macUsers: macs,
    );
  }

  /// طريق VPN الشركة (داخل نطاقها) — بطلبه هنا لا بـ[VpnNowApi.route]: ذاك يحفظ حال الشركة المفتوحة.
  static Future<MergedVpnRoute> _route() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/conn-vpn/route',
          options: Options(validateStatus: (s) => s != null && s < 500));
      final d = r.data?['data'];
      if (r.statusCode != 200 || r.data?['success'] != true || d is! Map || d['linked'] is! bool) return MergedVpnRoute.unknown;
      return d['linked'] == true ? MergedVpnRoute.linked : MergedVpnRoute.missing;
    } catch (_) {
      return MergedVpnRoute.unknown;
    }
  }

  /// حدود الشركة (داخل نطاقها) بلا مخبأ المفتوحة؛ تعذّرت ⇒ الافتراضيّة ومُعلَنة (لا حدود شركةٍ أخرى).
  static Future<({CheckLimits limits, bool complete})> _limits() async {
    AgentVitalsStatus? vitals;
    ConnectionAlertThresholds? subs;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/agent-alerts/vitals');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) vitals = AgentVitalsStatus.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {}
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/settings');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) subs = ConnectionAlertThresholds.fromJson(Map<String, dynamic>.from(d));
    } catch (_) {}
    final s = vitals?.settings;
    final ct = subs ?? ConnectionAlertThresholds.defaults;
    return (
      complete: vitals != null && subs != null,
      limits: CheckLimits(
        cpuMax: s?.cpuMax ?? 90,
        tempMax: s?.tempMax ?? 80,
        linkSignalMin: s?.signalMin ?? -80,
        linkCcqMin: s?.ccqMin ?? 50,
        subSignal: ct.signalDbm,
        subCcq: ct.ccqPct,
        fiberRxMin: ct.fiberRxDbm,
        voltBase: {for (final p in vitals?.power ?? const <AgentVitalPower>[]) p.id: p.base},
        voltBelow: {for (final p in vitals?.power ?? const <AgentVitalPower>[]) p.id: p.alertBelow},
      ),
    );
  }

  /// مشتركو الشركة (قائمة «كل الشركات» المخبّأة) — الكبيرة بلا قائمة ⇒ بلا مطابقة، والنسخ يبقى.
  static Future<List<Subscriber>?> _subscribers(MergedCompany c) async {
    try {
      return (await MergedSubscribers.fetchCompany(c).timeout(const Duration(seconds: 25))).rows;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _gen++;
    _inner?.dispose();
    _inner = null;
    super.dispose();
  }
}
