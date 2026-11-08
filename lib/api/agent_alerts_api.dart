import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'alerts_page.dart';
import 'api_client.dart';

/// «تنبيهات أجهزتي» (٤ نوفمبر — الخادم server/agentAlerts.js): «طفى/رجع» لأجهزة شبكة الوكيل يقرّرها الخادم من جولات هذا التطبيق على
/// شبكته (probe-results) ومن نبضه عبر VPN لمن ربطه وفعّل «الاتصال العكسي»، مجمَّعةً (الشبكة كلّها/البرج) وبإشعارٍ يتجاوز ساعات الهدوء.
/// حين يعمل الخادم لهذه الشركة يسكت تنبيه الهاتف المحلّيّ ([shouldFireLocalAlerts]) — لا إشعاران للانطفاء نفسه.

class AgentAlertDevice {
  const AgentAlertDevice({required this.id, required this.name, this.type, this.place, this.sinceMs, this.untilMs});
  final int id;
  final String name;
  final String? type;

  /// «برج «النصر»» أو «منطقة «الحيّ»» — كما يسمّيها الخادم
  final String? place;
  final int? sinceMs;

  /// المتذبذب: مسكوتٌ عنه حتى
  final int? untilMs;

  static AgentAlertDevice? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    if (id == null) return null;
    return AgentAlertDevice(
      id: id,
      name: '${j['name'] ?? '#$id'}',
      type: j['type']?.toString(),
      place: j['place']?.toString(),
      sinceMs: (j['since_ms'] as num?)?.toInt(),
      untilMs: (j['until_ms'] as num?)?.toInt(),
    );
  }
}

/// هل يفحص الخادم شبكتك عن بُعد؟ (heartbeat.remoteOf بالخادم)
class AgentAlertRemote {
  const AgentAlertRemote({required this.on, this.why, this.via, this.healthy = false, this.lastMs});
  final bool on;

  /// off · vpn_off · not_linked · own · template · reverse_off
  final String? why;
  final String? via;
  final bool healthy;
  final int? lastMs;

  static AgentAlertRemote? fromJson(Object? j) {
    if (j is! Map) return null;
    return AgentAlertRemote(
      on: j['on'] == true,
      why: j['why']?.toString(),
      via: j['via']?.toString(),
      healthy: j['healthy'] == true,
      lastMs: (j['last_ms'] as num?)?.toInt(),
    );
  }

  /// «ربط VPN» يحلّها (فعّل «الاتصال العكسي» أو اربط) — زرٌّ إليها
  bool get fixableInVpn => why == 'reverse_off' || why == 'not_linked';

  /// سطرٌ للوكيل بكلماتٍ يفهمها
  String get text {
    if (on) return healthy ? 'والخادم يفحصها عبر الـVPN كلّ دقيقة وأنت بعيد' : 'والخادم يفحصها عبر الـVPN — النفق يعيد الاتّصال الآن';
    switch (why) {
      case 'reverse_off':
        return 'فعّل «الاتصال العكسي» في «ربط VPN» ليفحصها الخادم وأنت بعيد عن شبكتك';
      case 'not_linked':
        return 'اربط VPN بنظامنا ليفحصها الخادم وأنت بعيد عن شبكتك';
      case 'own':
      case 'template':
        return 'الخادم لا يفحصها عبر يوزر الـVPN مالتك: اتّصالٌ دائم به يقفل دخولك أنت — تُراقَب من موبايلك وأنت على شبكتك';
      default:
        return 'الفحص عن بُعد غير مفتوح لحسابك بعد — تُراقَب من موبايلك وأنت على شبكتك';
    }
  }
}

class AgentAlertsStatus {
  const AgentAlertsStatus({
    required this.available,
    this.dryRun = false,
    this.enabled = true,
    this.notifyUp = true,
    this.canUse = false,
    this.canEdit = false,
    this.remote,
    this.devices = 0,
    this.monitored = 0,
    this.down = const [],
    this.quiet = const [],
    this.networkDown = false,
    this.lastAppMs,
    this.lastVpnMs,
  });

  final bool available;
  final bool dryRun;
  final bool enabled;
  final bool notifyUp;
  final bool canUse;
  final bool canEdit;
  final AgentAlertRemote? remote;
  final int devices;
  final int monitored;
  final List<AgentAlertDevice> down;
  final List<AgentAlertDevice> quiet;
  final bool networkDown;
  final int? lastAppMs;
  final int? lastVpnMs;

  static const off = AgentAlertsStatus(available: false);

  factory AgentAlertsStatus.fromJson(Map<String, dynamic> j) {
    List<AgentAlertDevice> list(Object? v) =>
        v is List ? v.map(AgentAlertDevice.fromJson).whereType<AgentAlertDevice>().toList() : const [];
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return AgentAlertsStatus(
      available: j['available'] == true,
      dryRun: j['dry_run'] == true,
      enabled: j['enabled'] != false,
      notifyUp: j['notify_up'] != false,
      canUse: j['can_use'] == true,
      canEdit: j['can_edit'] == true,
      remote: AgentAlertRemote.fromJson(j['remote']),
      devices: n(j['devices']),
      monitored: n(j['monitored']),
      down: list(j['down']),
      quiet: list(j['quiet']),
      networkDown: j['network_down'] == true,
      lastAppMs: (j['last_app_ms'] as num?)?.toInt(),
      lastVpnMs: (j['last_vpn_ms'] as num?)?.toInt(),
    );
  }
}

class AgentAlertEvent {
  const AgentAlertEvent({required this.id, required this.kind, this.title, this.detail, this.devices = const [], this.source, this.push = 'none', this.atMs});
  final int id;

  /// down · up · tower_down · tower_up · network_down · network_up · flap · blip
  final String kind;
  final String? title;
  final String? detail;
  final List<int> devices;
  final String? source;

  /// sent · failed · none · dry · off
  final String push;
  final int? atMs;

  bool get isUp => kind == 'up' || kind == 'tower_up' || kind == 'network_up';

  static AgentAlertEvent? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    if (id == null) return null;
    final d = j['devices'];
    return AgentAlertEvent(
      id: id,
      kind: '${j['kind'] ?? ''}',
      title: j['title']?.toString(),
      detail: j['detail']?.toString(),
      devices: d is List ? d.map((x) => (x as num?)?.toInt()).whereType<int>().toList() : const [],
      source: j['source']?.toString(),
      push: '${j['push'] ?? 'none'}',
      atMs: (j['at_ms'] as num?)?.toInt(),
    );
  }
}

/// «القراءات الحسّاسة» (المرحلة ٢ — server/agentVitals.js): حدود الوكيل.
class AgentVitalSettings {
  const AgentVitalSettings({
    this.enabled = true,
    this.voltOn = true,
    this.cpuMax = 90,
    this.tempMax = 80,
    this.voltDropPct = 15,
    this.signalDropDb = 8,
    this.signalMin = -80,
    this.ccqMin = 50,
  });
  final bool enabled;

  /// مفتاح الكهرباء وحدها (٦ نوفمبر — المالك: «قسم الكهرباء… يكون توكل»): مطفأ ⇒ لا إشعار نزولٍ ولا «رجعت»؛ القراءة تستمرّ.
  final bool voltOn;
  final int cpuMax, tempMax, voltDropPct, signalDropDb, signalMin, ccqMin;

  static AgentVitalSettings fromJson(Object? j) {
    if (j is! Map) return const AgentVitalSettings();
    int n(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    return AgentVitalSettings(
      enabled: j['enabled'] != false,
      voltOn: j['volt_on'] != false,
      cpuMax: n('cpu_max', 90),
      tempMax: n('temp_max', 80),
      voltDropPct: n('volt_drop_pct', 15),
      signalDropDb: n('signal_drop_db', 8),
      signalMin: n('signal_min', -80),
      ccqMin: n('ccq_min', 50),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'volt_on': voltOn,
        'cpu_max': cpuMax,
        'temp_max': tempMax,
        'volt_drop_pct': voltDropPct,
        'signal_drop_db': signalDropDb,
        'signal_min': signalMin,
        'ccq_min': ccqMin,
      };

  AgentVitalSettings copyWith({bool? enabled, bool? voltOn, int? cpuMax, int? tempMax, int? voltDropPct, int? signalDropDb, int? signalMin, int? ccqMin}) =>
      AgentVitalSettings(
        enabled: enabled ?? this.enabled,
        voltOn: voltOn ?? this.voltOn,
        cpuMax: cpuMax ?? this.cpuMax,
        tempMax: tempMax ?? this.tempMax,
        voltDropPct: voltDropPct ?? this.voltDropPct,
        signalDropDb: signalDropDb ?? this.signalDropDb,
        signalMin: signalMin ?? this.signalMin,
        ccqMin: ccqMin ?? this.ccqMin,
      );
}

/// مقياسٌ في الإنذار الآن: volt · temp · cpu · signal · ccq.
class AgentVitalAlert {
  const AgentVitalAlert({required this.id, required this.name, required this.metric, this.place, this.value, this.base, this.sinceMs});
  final int id;
  final String name;
  final String metric;
  final String? place;
  final double? value;
  final double? base;
  final int? sinceMs;

  static AgentVitalAlert? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    if (id == null) return null;
    return AgentVitalAlert(
      id: id,
      name: '${j['name'] ?? '#$id'}',
      metric: '${j['metric'] ?? ''}',
      place: j['place']?.toString(),
      value: (j['value'] as num?)?.toDouble(),
      base: (j['base'] as num?)?.toDouble(),
      sinceMs: (j['since_ms'] as num?)?.toInt(),
    );
  }
}

/// الكهرباء بالفولت لجهازٍ له معدّل (المالك ٤ نوفمبر: «مفروض توضح كم يعني للنسبه»): فولتيّته الطبيعيّة وحدّ تنبيهه.
class AgentVitalPower {
  const AgentVitalPower({required this.id, required this.name, required this.base, required this.alertBelow, this.place, this.value, this.alert = false});
  final int id;
  final String name;
  final String? place;
  final double base;
  final double alertBelow;
  final double? value;
  final bool alert;

  static AgentVitalPower? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = (j['id'] as num?)?.toInt();
    final base = (j['base'] as num?)?.toDouble();
    final below = (j['alert_below'] as num?)?.toDouble();
    if (id == null || base == null || below == null) return null;
    return AgentVitalPower(
      id: id,
      name: '${j['name'] ?? '#$id'}',
      place: j['place']?.toString(),
      base: base,
      alertBelow: below,
      value: (j['value'] as num?)?.toDouble(),
      alert: j['state'] == 'alert',
    );
  }
}

class AgentVitalsStatus {
  const AgentVitalsStatus({
    required this.available,
    this.dryRun = false,
    this.settings = const AgentVitalSettings(),
    this.canUse = false,
    this.canEdit = false,
    this.watched = 0,
    this.alerts = const [],
    this.power = const [],
    this.powerLearning = 0,
  });
  final bool available;
  final bool dryRun;
  final AgentVitalSettings settings;

  /// الكهرباء بالفولت لكلّ جهازٍ له معدّل، وكم جهازاً يتعلّم معدّله بعد
  final List<AgentVitalPower> power;
  final int powerLearning;
  final bool canUse;
  final bool canEdit;

  /// مقاييس تحت المراقبة (جهاز × مقياس)
  final int watched;
  final List<AgentVitalAlert> alerts;

  static const off = AgentVitalsStatus(available: false);

  factory AgentVitalsStatus.fromJson(Map<String, dynamic> j) {
    final a = j['alerts'];
    final p = j['power'];
    return AgentVitalsStatus(
      available: j['available'] == true,
      dryRun: j['dry_run'] == true,
      settings: AgentVitalSettings.fromJson(j['settings']),
      canUse: j['can_use'] == true,
      canEdit: j['can_edit'] == true,
      watched: (j['watched'] as num?)?.toInt() ?? 0,
      alerts: a is List ? a.map(AgentVitalAlert.fromJson).whereType<AgentVitalAlert>().toList() : const [],
      power: p is List ? p.map(AgentVitalPower.fromJson).whereType<AgentVitalPower>().toList() : const [],
      powerLearning: (j['power_learning'] as num?)?.toInt() ?? 0,
    );
  }
}

class AgentAlertsApi {
  AgentAlertsApi._();

  /// آخر حالٍ قُرئ لهذه الشركة — زرّ التنبيهات بقسم الأجهزة وإسكات تنبيه الهاتف المحلّيّ
  static AgentAlertsStatus? cached;

  /// الخادم يقرّر «طفى/رجع» لهذه الشركة ⇒ لا تنبيهٌ محلّيّ من الهاتف للانطفاء نفسه (إشعاران لحدثٍ واحد).
  static bool get serverActive => cached?.available == true && cached!.enabled;
  static bool shouldFireLocalAlerts() => !serverActive;

  /// شركةٌ أخرى فُتحت ⇒ حالها يُقرأ من جديد (لا يُسكت تنبيهها بحال غيرها)
  static void forget() {
    cached = null;
    vitalsCached = null;
  }

  static String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return '${d['message']}';
    }
    return fallback;
  }

  /// null = تعذّر (شبكة/خادم)؛ [AgentAlertsStatus.off] = غير مفتوحٍ لحسابك أو لا صلاحيّة
  static Future<AgentAlertsStatus?> status() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/agent-alerts/status');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) {
        final st = AgentAlertsStatus.fromJson(Map<String, dynamic>.from(d));
        cached = st;
        return st;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        cached = AgentAlertsStatus.off;
        return AgentAlertsStatus.off;
      }
      if (kDebugMode) debugPrint('⚠️ agent-alerts status: ${e.message}');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ agent-alerts status: $e');
    }
    return null;
  }

  static Future<({bool ok, String? message})> save({bool? enabled, bool? notifyUp}) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/agent-alerts/settings', data: {
        if (enabled != null) 'enabled': enabled,
        if (notifyUp != null) 'notify_up': notifyUp,
      });
      return (ok: r.data?['success'] == true, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, message: _msg(e, 'تعذّر الحفظ'));
    }
  }

  /// حال «القراءات الحسّاسة» — آخر قراءةٍ لهذه الشركة: هل يُرفع ما يقرؤه التطبيق ([VitalsReporter]) وتُعاد القراءة كلّ ١٠ د
  static AgentVitalsStatus? vitalsCached;

  static Future<AgentVitalsStatus?> vitalsStatus() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/agent-alerts/vitals');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) {
        final st = AgentVitalsStatus.fromJson(Map<String, dynamic>.from(d));
        vitalsCached = st;
        return st;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 || e.response?.statusCode == 404) {
        vitalsCached = AgentVitalsStatus.off;
        return AgentVitalsStatus.off;
      }
      if (kDebugMode) debugPrint('⚠️ agent-vitals status: ${e.message}');
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ agent-vitals status: $e');
    }
    return null;
  }

  static Future<({bool ok, String? message})> saveVitals(AgentVitalSettings s) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/agent-alerts/vitals/settings', data: s.toJson());
      return (ok: r.data?['success'] == true, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, message: _msg(e, 'تعذّر الحفظ'));
    }
  }

  /// قراءاتٌ ⇒ هل ما زال الخادم يريدها (active)؛ null = تعذّر (يُعاد لاحقاً).
  static Future<bool?> uploadVitals(List<Map<String, dynamic>> readings) async {
    if (readings.isEmpty) return true;
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/agent-alerts/vitals', data: {'readings': readings});
      final d = r.data?['data'];
      return d is Map ? d['active'] == true : false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 403 || e.response?.statusCode == 404) return false;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// صفحةٌ من السجلّ («تحميل المزيد» — ٩ نوفمبر، المالك: «تنبيهات المشتركين والأجهزة — خلّي بيها ١٠ قراءات وتحميل المزيد»): [size]
  /// الأحدث قبل السطر [before] (رقم آخر ما عُرض — الخادم يقبله منذ ٤ نوفمبر)، و+١ لتعرف أنّ بعدها المزيد. null = تعذّر.
  static Future<AlertsPage<AgentAlertEvent>?> logPage({String? before, int size = 10}) async {
    final rows = await log(limit: size + 1, before: before == null ? null : int.tryParse(before));
    if (rows == null) return null;
    final page = rows.take(size).toList();
    final more = rows.length > size;
    return AlertsPage(page, hasMore: more, next: more && page.isNotEmpty ? '${page.last.id}' : null);
  }

  /// الأحدث أوّلاً؛ before = أقدم ما عندك (رقم السطر). null = تعذّر.
  static Future<List<AgentAlertEvent>?> log({int limit = 50, int? before}) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/agent-alerts/log', queryParameters: {
        'limit': limit,
        if (before != null) 'before': before,
      });
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) {
        final items = d['items'];
        return items is List ? items.map(AgentAlertEvent.fromJson).whereType<AgentAlertEvent>().toList() : const [];
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ agent-alerts log: $e');
    }
    return null;
  }
}
