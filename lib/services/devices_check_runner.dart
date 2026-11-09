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
import '../api/mikrotik_binary_api.dart' show MikrotikBinaryException;
import '../api/snmp_client.dart' show SnmpException, SnmpTimeoutException;
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
    final deadline = piped ? 45 : 25;
    try {
      final p = await (debugFetch?.call(d) ?? DeviceVitals.fetch(d, detailed: true)).timeout(Duration(seconds: deadline));
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
    } catch (e) {
      return DevicesCheck.evaluate(
        d: d,
        alive: alive ?? true,
        ms: probe?.responseMs,
        loss: probe?.packetLoss,
        unreadReason: unreadReason(e, deadline: deadline, serviceOk: probe?.serviceOk),
        limits: limits,
        prev: prev,
      );
    }
  }

  // ── لماذا لم يُقرأ ────────────────────────────────────────────────

  static const _service = 'يردّ، لكن خدمة الإدارة لا تجيب — تأكّد من المنفذ والبروتوكول';

  /// لماذا لم تُقرأ معلومات جهازٍ يردّ — السبب الحقيقيّ بكلمة.
  ///
  /// ٩ نوفمبر (المالك: «مرات اكو اجهزه بالنظام يتفحها ويعرض معلومات بس بقسم فحص الاجهزه يكول لم يقرا»): كان كلّ فشلٍ «تأكّد من
  /// اسم المستخدم والرمز» — ومهلة الجهاز البطيء، والمنفذ المقفول، وزحمة ممرّ الـVPN، وتعذّر جلب بيانات الدخول من خادمنا كلّها غيره.
  /// رسالة الدخول الآن لرفض الدخول الحقيقيّ وحده. [deadline] مهلة القراءة كلّها (ث)، و[serviceOk] جواب خدمة الإدارة بالبنك (null
  /// = لم يُعرف) — يفصل «بطيء» عن «لا يُفتح» حين تأتي المهلة من داخل القارئ.
  @visibleForTesting
  static String unreadReason(Object e, {required int deadline, bool? serviceOk}) {
    // ١) المهلة كلّها — الجهاز يردّ لكنّ قراءته الكاملة أطول منها
    if (e is TimeoutException) return 'بطيء — لم تكتمل قراءته خلال $deadlineث';
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
      return 'يردّ، لكن رُفض الدخول — تأكّد من اسم المستخدم والرمز';
    }
    // ٤) دخل وصلاحيّته لا تكفي للقراءة (مجموعة المستخدم، community بلا قراءة)
    if (low.contains('not enough permissions') || s.contains('صلاحيّة القراءة') || s.contains('صلاحيّات المستخدم')) {
      return 'يردّ، لكن مستخدمه بلا صلاحيّة قراءة — راجع صلاحيّاته على الجهاز';
    }
    // ٥) بيانات دخوله من خادمنا: الطلب فشل (٥٠٣ عابرة…) أو ناقصة
    if (e is DioException || s.contains('فشل جلب المعلومات')) {
      return 'تعذّر جلب بيانات دخوله من الخادم — أعد الفحص بعد قليل';
    }
    if (s.contains('بيانات دخول ناقصة') ||
        s.contains('لم يتم إعداد بيانات الدخول') ||
        s.contains('لم تُحفظ الـcommunity') ||
        s.contains('أدخل الـcommunity')) {
      return 'بيانات دخوله ناقصة — أكملها من صفحة الجهاز';
    }
    if (s.contains('غير مدعومة')) return 'علامته لا تُقرأ بالفحص';
    final inTime = e is SnmpTimeoutException ||
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
