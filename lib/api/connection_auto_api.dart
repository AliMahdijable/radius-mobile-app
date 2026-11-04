import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'company_route.dart';

/// «تنبيه المشترك» التلقائيّ (٣ نوفمبر — الخادم server/connAlertsAuto.js).
///
/// التطبيق يقيس أجهزة المشتركين (موجة فحص القائمة) ويرفع القراءات الخام ([uploadReadings])، والخادم وحده يقرّر بحدود الوكيل
/// ويؤكّد (قراءتان بينهما [ConnAutoSettings.confirmMin]) ويضع «بانتظار موافقتك» (الافتراضيّ) أو يرسل تلقائيّاً في ساعات الوكيل
/// وتحت سقفه، ويذكّر كلّ [ConnAutoSettings.remindDays] حتى [ConnAutoSettings.maxSends]. خلف مفتاحٍ بالخادم: حسابٌ لم يُفتح له ⇒
/// [ConnAutoStatus.available] false ولا يظهر شيء.
class ConnAutoSettings {
  const ConnAutoSettings({
    this.mode = 'approval',
    this.remindDays = 3,
    this.maxSends = 3,
    this.dailyCap = 30,
    this.hourFrom = 10,
    this.hourTo = 20,
    this.confirmMin = 30,
    this.kinds = kAllKinds,
  });

  static const kAllKinds = <String>['cable', 'signal', 'ccq', 'fiber_rx', 'fiber_temp'];

  /// خيارات «تأكّد من المشكلة بعد» بالدقائق (٣ نوفمبر — المالك؛ الخادم AUTO_LIMITS.confirm_min.steps).
  static const kConfirmSteps = <int>[3, 5, 10, 15, 20, 25, 30];

  /// manual (يدويّ: لا شيء تلقائيّ) · approval (بموافقتي) · auto (تلقائيّ)
  final String mode;
  final int remindDays;
  final int maxSends;
  final int dailyCap;
  final int hourFrom;
  final int hourTo;
  final int confirmMin;
  final List<String> kinds;

  factory ConnAutoSettings.fromJson(Map<String, dynamic> j) {
    int i(String k, int d) => (j[k] is num) ? (j[k] as num).toInt() : int.tryParse('${j[k]}') ?? d;
    return ConnAutoSettings(
      mode: const ['manual', 'approval', 'auto'].contains(j['mode']) ? j['mode'] as String : 'approval',
      remindDays: i('remind_days', 3),
      maxSends: i('max_sends', 3),
      dailyCap: i('daily_cap', 30),
      hourFrom: i('hour_from', 10),
      hourTo: i('hour_to', 20),
      confirmMin: i('confirm_min', 30),
      kinds: j['kinds'] is List ? (j['kinds'] as List).map((e) => '$e').where(kAllKinds.contains).toList() : kAllKinds,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'remind_days': remindDays,
        'max_sends': maxSends,
        'daily_cap': dailyCap,
        'hour_from': hourFrom,
        'hour_to': hourTo,
        'confirm_min': confirmMin,
        'kinds': kinds,
      };

  ConnAutoSettings copyWith({
    String? mode,
    int? remindDays,
    int? maxSends,
    int? dailyCap,
    int? hourFrom,
    int? hourTo,
    int? confirmMin,
    List<String>? kinds,
  }) =>
      ConnAutoSettings(
        mode: mode ?? this.mode,
        remindDays: remindDays ?? this.remindDays,
        maxSends: maxSends ?? this.maxSends,
        dailyCap: dailyCap ?? this.dailyCap,
        hourFrom: hourFrom ?? this.hourFrom,
        hourTo: hourTo ?? this.hourTo,
        confirmMin: confirmMin ?? this.confirmMin,
        kinds: kinds ?? this.kinds,
      );

  @override
  bool operator ==(Object other) =>
      other is ConnAutoSettings &&
      other.mode == mode &&
      other.remindDays == remindDays &&
      other.maxSends == maxSends &&
      other.dailyCap == dailyCap &&
      other.hourFrom == hourFrom &&
      other.hourTo == hourTo &&
      other.confirmMin == confirmMin &&
      listEquals([...other.kinds]..sort(), [...kinds]..sort());

  @override
  int get hashCode => Object.hash(mode, remindDays, maxSends, dailyCap, hourFrom, hourTo, confirmMin, kinds.length);
}

class ConnAutoStatus {
  const ConnAutoStatus({
    required this.available,
    this.dryRun = false,
    this.alertsEnabled = false,
    this.settings = const ConnAutoSettings(),
    this.counts = const {},
    this.inWindow = false,
    this.canUse = true,
    this.canEdit,
  });

  static const off = ConnAutoStatus(available: false);

  final bool available;

  /// محاكاة: كلّ شيءٍ كما هو إلّا أنّ «الإرسال» سطرٌ في السجلّ — لا رسالة تصل للمشترك.
  final bool dryRun;

  /// «تنبيه المشترك» نفسه مفعّل (مفتاح الشاشة) — بدونه لا يُقاس ولا يُرسل شيء.
  final bool alertsEnabled;
  final ConnAutoSettings settings;

  /// pending · queued · watching · sent · skipped · muted · sent_today
  final Map<String, int> counts;
  final bool inWindow;

  /// قسم «تنبيهات المشتركين» مفتوحٌ لهذا الفاعل؟ الموظّف بمفتاحه conn_alerts.use وغير مقيَّدٍ بمديرٍ فرعيّ (٤ نوفمبر — مستقلٌّ عن مفتاح
  /// الإشعار). خادمٌ أقدم لا يرسله ⇒ true كما كان.
  final bool canUse;

  /// إعدادات الإرسال قابلةٌ للتعديل (+whatsapp.templates)؛ null من خادمٍ أقدم ⇒ الشاشة تقرّر بصلاحيّاتها كما كانت.
  final bool? canEdit;

  int count(String k) => counts[k] ?? 0;

  ConnAutoStatus withSettings(ConnAutoSettings s) => ConnAutoStatus(
      available: available, dryRun: dryRun, alertsEnabled: alertsEnabled, settings: s, counts: counts, inWindow: inWindow,
      canUse: canUse, canEdit: canEdit);

  /// يُرفع القياس؟ (الحساب مفتوح، والتنبيه مفعّل، والوضع غير يدويّ)
  bool get collects => available && alertsEnabled && settings.mode != 'manual';

  factory ConnAutoStatus.fromJson(Map<String, dynamic> j) {
    if (j['available'] != true) return off;
    final c = <String, int>{};
    if (j['counts'] is Map) {
      (j['counts'] as Map).forEach((k, v) => c['$k'] = v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    }
    return ConnAutoStatus(
      available: true,
      dryRun: j['dry_run'] == true,
      alertsEnabled: j['alerts_enabled'] == true,
      settings: j['settings'] is Map ? ConnAutoSettings.fromJson(Map<String, dynamic>.from(j['settings'] as Map)) : const ConnAutoSettings(),
      counts: c,
      inWindow: j['in_window'] == true,
      canUse: j['can_use'] != false,
      canEdit: j['can_edit'] is bool ? j['can_edit'] as bool : null,
    );
  }
}

class ConnAlertProblem {
  const ConnAlertProblem({required this.kind, required this.label, required this.text});
  final String kind;
  final String label;

  /// القيمة كما تدخل الرسالة («‎-70 dBm» · «يقرأ 10 ميكا»)
  final String text;
}

/// مشتركٌ في «تنبيه المشترك» التلقائيّ: حالته ومشاكله الحاليّة وأوقاتها.
class ConnAlertCase {
  const ConnAlertCase({
    required this.key,
    required this.state,
    this.idx,
    this.username,
    this.name,
    this.phone,
    this.problems = const [],
    this.firstBadAt,
    this.lastReadingAt,
    this.confirmedAt,
    this.lastSentAt,
    this.sends = 0,
    this.muted = false,
    this.lastError,
  });

  final String key;

  /// watching · pending · queued · sent · skipped · ok
  final String state;
  final String? idx;
  final String? username;
  final String? name;
  final String? phone;
  final List<ConnAlertProblem> problems;
  final DateTime? firstBadAt;
  final DateTime? lastReadingAt;
  final DateTime? confirmedAt;
  final DateTime? lastSentAt;
  final int sends;
  final bool muted;
  final String? lastError;

  String get title {
    final n = (name ?? '').trim();
    return n.isNotEmpty ? n : (username ?? key);
  }

  static DateTime? _ms(Object? v) {
    final n = v is num ? v.toInt() : int.tryParse('$v');
    return n == null || n <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(n);
  }

  factory ConnAlertCase.fromJson(Map<String, dynamic> j) => ConnAlertCase(
        key: '${j['key']}',
        state: '${j['state'] ?? 'ok'}',
        idx: j['idx']?.toString(),
        username: j['username']?.toString(),
        name: j['name']?.toString(),
        phone: j['phone']?.toString(),
        problems: j['problems'] is List
            ? (j['problems'] as List)
                .whereType<Map>()
                .map((p) => ConnAlertProblem(kind: '${p['kind']}', label: '${p['label'] ?? p['kind']}', text: '${p['text'] ?? ''}'))
                .toList()
            : const [],
        firstBadAt: _ms(j['first_bad_ms']),
        lastReadingAt: _ms(j['last_reading_ms']),
        confirmedAt: _ms(j['confirmed_ms']),
        lastSentAt: _ms(j['last_sent_ms']),
        sends: j['sends'] is num ? (j['sends'] as num).toInt() : 0,
        muted: j['muted'] == true,
        lastError: (j['last_error'] ?? '').toString().trim().isEmpty ? null : '${j['last_error']}',
      );
}

class ConnAlertLogEntry {
  const ConnAlertLogEntry({required this.action, this.name, this.kinds = const [], this.dry = false, this.detail, this.at});
  final String action;
  final String? name;
  final List<String> kinds;
  final bool dry;
  final String? detail;
  final DateTime? at;
}

/// نتيجة «افحص الآن» (٤ نوفمبر): من شبكة الوكيل (التطبيق نفسه — local) أو عبر VPN الخادم (vpn)، أو لم يُفحص (none).
@immutable
class ConnCheckResult {
  const ConnCheckResult({required this.ok, required this.via, required this.message, this.readable, this.problems, this.atMs});
  final bool ok;
  final String via;
  final String message;
  final int? readable, problems;
  final int? atMs;

  static ConnCheckResult fromVpn(Object? j) {
    if (j is! Map) return const ConnCheckResult(ok: false, via: 'vpn', message: 'تعذّر الفحص الآن — حاول بعد قليل');
    int? n(String k) => j[k] is num ? (j[k] as num).toInt() : null;
    return ConnCheckResult(
      ok: j['ok'] == true,
      via: 'vpn',
      message: '${j['message'] ?? ''}'.trim().isEmpty ? 'تعذّر الفحص الآن — حاول بعد قليل' : '${j['message']}',
      readable: n('readable'),
      problems: n('problems'),
      atMs: n('at_ms'),
    );
  }
}

class ConnectionAutoApi {
  ConnectionAutoApi._();

  /// آخر حالةٍ معروفة (شارة «بانتظار موافقتك» وقرار رفع القراءات).
  static final ValueNotifier<ConnAutoStatus> status = ValueNotifier(ConnAutoStatus.off);

  /// يزيد بعد كلّ إجراءٍ ناجح (أرسل/تجاهل/منع/أرسل الآن…) ⇒ كلّ تبويبات «تنبيهات المشتركين» تُعيد التحميل (المالك ٣ نوفمبر: «من
  /// اسوي اي حدث ميتحدث بالكل الاقسام البقية الا اعمل رفريش»).
  static final ValueNotifier<int> changes = ValueNotifier(0);

  /// صفحة القوائم (المالك: «كل صفحه خلي ماكس عرض ١٠ وتحميل المزيد»).
  static const pageSize = 10;
  static DateTime? _at;
  static Future<ConnAutoStatus>? _flight;
  static const _ttl = Duration(minutes: 5);

  /// «كل الشركات» (٤ نوفمبر): حالة كلّ شركةٍ برفع قراءاتها — طلبٌ موجَّه بكاشٍ لكلّ مفتاح، لا يمسّ [status] (شارة الشركة المفتوحة
  /// وقسمها).
  static final Map<String, ({ConnAutoStatus st, DateTime at})> _companies = {};

  @visibleForTesting
  static void debugReset() {
    status.value = ConnAutoStatus.off;
    _at = null;
    _flight = null;
    _companies.clear();
  }

  static Future<ConnAutoStatus> load({bool force = false}) {
    if (!force && _at != null && DateTime.now().difference(_at!) < _ttl) return Future.value(status.value);
    final running = _flight;
    // 🐛 ٣ نوفمبر: «إجبار» كان يرجع طلباً بدأ قبل الحفظ فيعيد الإعدادات القديمة ⇒ طلبٌ جديدٌ بعد الجاري
    if (running != null && !force) return running;
    final next = (running ?? Future<ConnAutoStatus>.value(status.value)).then((_) => _load());
    _flight = next;
    return next.whenComplete(() {
      if (identical(_flight, next)) _flight = null;
    });
  }

  static Future<ConnAutoStatus> _load() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/auto');
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) {
        status.value = ConnAutoStatus.fromJson(Map<String, dynamic>.from(d));
        _at = DateTime.now();
      }
    } catch (e) {
      // خادمٌ أقدم أو بلا صلاحيّة ⇒ الميزة غائبة كما كانت
      if (!kReleaseMode) debugPrint('🔴 connection-alerts/auto: $e');
    }
    return status.value;
  }

  /// حالة الشركة [companyKey] لرفع القراءات: null ⇒ الشركة المفتوحة ([load])؛ وإلّا طلبٌ موجَّه (x-company-key) يُحفظ [_ttl]،
  /// وفشلُه أو شركةٌ لا يُوجَّه لها المسار (FTTH والشركات المُضافة) ⇒ off حتى المهلة. مفتاحٌ غير صالح ⇒ off (لا طلب بلا توجيه).
  static Future<ConnAutoStatus> statusOf(String? companyKey) async {
    if (companyKey == null) return load();
    if (!CompanyRoute.keyRe.hasMatch(companyKey)) return ConnAutoStatus.off;
    final hit = _companies[companyKey];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) return hit.st;
    var st = ConnAutoStatus.off;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/auto',
          options: Options(extra: {'companyKey': companyKey}));
      final d = r.data?['data'];
      if (r.data?['success'] == true && d is Map) st = ConnAutoStatus.fromJson(Map<String, dynamic>.from(d));
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 connection-alerts/auto (company): $e');
    }
    _companies[companyKey] = (st: st, at: DateTime.now());
    return st;
  }

  static String _msg(Object e, String fallback) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return '${d['message']}';
    }
    return fallback;
  }

  static Future<({bool ok, String? message})> save(ConnAutoSettings s) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>('/api/v2/connection-alerts/auto', data: s.toJson());
      if (r.data?['success'] == true) {
        // المحفوظ كما ردّه الخادم (لا قراءةٌ ثانية قد تسبقها قراءةٌ قديمة)
        final d = r.data?['data'];
        final saved = d is Map && d['settings'] is Map ? ConnAutoSettings.fromJson(Map<String, dynamic>.from(d['settings'] as Map)) : s;
        status.value = status.value.withSettings(saved);
        _at = DateTime.now();
        return (ok: true, message: r.data?['message']?.toString());
      }
      return (ok: false, message: r.data?['message']?.toString() ?? 'تعذّر الحفظ');
    } catch (e) {
      return (ok: false, message: _msg(e, 'تعذّر الحفظ — تحقّق من الاتّصال'));
    }
  }

  /// قراءاتٌ خام (دفعة ≤ ٤٠٠). صامتة: فشلها لا يُزعج أحداً — الموجة التالية تعيدها. null = لم تُقبل؛ وإلّا مواعيد إعادة القياس
  /// لمن صار «تحت المراقبة» (username ⇒ الموعد) — يقيسه التطبيق وحده حينها فيتأكّد في وقته (٣ نوفمبر). [companyKey]: صفوف
  /// شركةٍ من «كل الشركات» ⇒ الطلب موجَّهٌ لها.
  static Future<Map<String, DateTime>?> uploadReadings(List<Map<String, dynamic>> readings, {String? companyKey}) async =>
      (await uploadReadingsStats(readings, companyKey: companyKey))?.due;

  /// القراءات ⇒ الخادم، مع إحصاء ما فعلته (لـ«افحص الآن» من شبكة الوكيل): المقروء، ومن دخل «تحت المراقبة»، ومن تأكّد، ومن حُلّ.
  /// null = تعذّر (شبكة/خادم).
  static Future<({Map<String, DateTime> due, int usable, int watching, int confirmed, int resolved})?> uploadReadingsStats(
      List<Map<String, dynamic>> readings, {String? companyKey}) async {
    if (readings.isEmpty) return (due: const <String, DateTime>{}, usable: 0, watching: 0, confirmed: 0, resolved: 0);
    // قراءات شركةٍ أخرى لا تذهب للمفتوحة أبداً: مفتاحٌ غير صالح يُسقطه التوجيه بصمت ⇒ لا طلب
    if (companyKey != null && !CompanyRoute.keyRe.hasMatch(companyKey)) return null;
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/connection-alerts/readings',
          data: {'readings': readings}, options: companyKey == null ? null : Options(extra: {'companyKey': companyKey}));
      final d = r.data?['data'];
      if (d is Map && d['active'] == false) {
        // الخادم يقول: لا قياس (أُطفئ/صار يدويّاً) ⇒ تُحدَّث الحالة فيتوقّف الرفع؛ والشركة الموجَّهة تُقرأ حالتها من جديد بالموجة التالية
        if (companyKey == null) {
          unawaitedLoad();
        } else {
          _companies.remove(companyKey);
        }
      }
      if (r.data?['success'] != true) return null;
      final out = <String, DateTime>{};
      if (d is Map && d['recheck'] is List) {
        for (final x in (d['recheck'] as List).whereType<Map>()) {
          final u = '${x['username'] ?? ''}'.trim();
          final ms = x['due_ms'] is num ? (x['due_ms'] as num).toInt() : null;
          if (u.isNotEmpty && ms != null) out[u] = DateTime.fromMillisecondsSinceEpoch(ms);
        }
      }
      int n(String k) => d is Map && d[k] is num ? (d[k] as num).toInt() : 0;
      return (due: out, usable: n('usable'), watching: n('watching'), confirmed: n('confirmed'), resolved: n('resolved'));
    } catch (_) {
      return null;
    }
  }

  /// «افحص الآن» عبر VPN الخادم (٤ نوفمبر — حين يكون التطبيق خارج شبكة الوكيل): يبدأ جولةً واحدة ثمّ يستطلع حتى تكتمل. الخادم
  /// يعيد الفحص الجاري نفسه للضغطة المكرّرة.
  static Future<ConnCheckResult> vpnCheckNow({
    Duration every = const Duration(milliseconds: 2500),
    int maxPolls = 120,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/conn-vpn/check-now');
      final id = (r.data?['data'] as Map?)?['check_id']?.toString();
      if (id == null || id.isEmpty) {
        return ConnCheckResult(ok: false, via: 'vpn', message: r.data?['message']?.toString() ?? 'تعذّر الفحص الآن — حاول بعد قليل');
      }
      for (var i = 0; i < maxPolls; i++) {
        final p = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/conn-vpn/check-now/$id');
        final d = p.data?['data'];
        if (d is Map && d['state'] == 'done') return ConnCheckResult.fromVpn(d['result']);
        await Future<void>.delayed(every);
      }
      return const ConnCheckResult(ok: false, via: 'vpn', message: 'الفحص أطول من المعتاد — افتح الصفحة بعد قليل');
    } catch (e) {
      return ConnCheckResult(ok: false, via: 'vpn', message: _msg(e, 'تعذّر الفحص الآن — حاول بعد قليل'));
    }
  }

  /// «أرسل الآن» لمشتركٍ واحد (من «تحت المراقبة» أو «بانتظار موافقتك»): رسالةٌ مباشرة بطلبك.
  static Future<({bool ok, bool dry, String? message})> sendNow(String key) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/connection-alerts/queue/action',
          data: {'action': 'send_now', 'keys': [key]});
      final d = r.data?['data'];
      unawaitedLoad();
      if (r.data?['success'] == true) changes.value++;
      return (ok: r.data?['success'] == true, dry: d is Map && d['dry'] == true, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, dry: false, message: _msg(e, 'تعذّر الإرسال الآن — حاول بعد قليل'));
    }
  }

  static void unawaitedLoad() {
    load(force: true).ignore();
  }

  /// [limit] صفّاً على الأكثر (الخادم ≤٥٠٠) — الشاشة تطلب صفحتها + ١ لتعرف أنّ هناك المزيد.
  static Future<List<ConnAlertCase>> queue(String state, {int limit = 300}) async {
    final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/queue', queryParameters: {'state': state, 'limit': limit});
    final d = r.data?['data'];
    if (d is! Map || d['items'] is! List) return const [];
    return (d['items'] as List).whereType<Map>().map((m) => ConnAlertCase.fromJson(Map<String, dynamic>.from(m))).toList();
  }

  /// approve · skip · mute · unmute · requeue — أو «أرسل للكلّ» ([all])
  static Future<({bool ok, int done, String? message})> act(String action, List<String> keys, {bool all = false}) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/v2/connection-alerts/queue/action',
          data: {'action': action, if (all) 'all': true else 'keys': keys});
      final d = r.data?['data'];
      final done = d is Map && d['done'] is num ? (d['done'] as num).toInt() : 0;
      unawaitedLoad();
      if (r.data?['success'] == true) changes.value++;
      return (ok: r.data?['success'] == true, done: done, message: r.data?['message']?.toString());
    } catch (e) {
      return (ok: false, done: 0, message: _msg(e, 'تعذّر الآن — حاول بعد قليل'));
    }
  }

  static Future<List<ConnAlertLogEntry>> log({int limit = 100}) async {
    final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/connection-alerts/log', queryParameters: {'limit': limit});
    final d = r.data?['data'];
    if (d is! Map || d['items'] is! List) return const [];
    return (d['items'] as List).whereType<Map>().map((m) {
      final name = '${m['name'] ?? ''}'.trim();
      final user = '${m['username'] ?? ''}'.trim();
      final at = m['at_ms'] is num ? DateTime.fromMillisecondsSinceEpoch((m['at_ms'] as num).toInt()) : null;
      return ConnAlertLogEntry(
        action: '${m['action']}',
        name: name.isNotEmpty ? name : (user.isNotEmpty ? user : null),
        kinds: m['kinds'] is List ? (m['kinds'] as List).map((e) => '$e').toList() : const [],
        dry: m['dry'] == true,
        detail: m['detail']?.toString(),
        at: at,
      );
    }).toList();
  }
}
