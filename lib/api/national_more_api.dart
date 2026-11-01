import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/provider_service.dart';
import 'api_client.dart';
import 'national_portal_api.dart';

/// المشروع الوطنيّ — أقسام البوّابة الباقية (١ نوفمبر — المالك: «اقسام البوابة البقية افضل تمضي بيها وتكملها»):
/// «الجلسات» (المتّصلون وغير المتّصلين)، «فريقي» (مستخدمو حساب الشريك وحدود محافظهم — بلا هاتفٍ ولا بريد أبداً)، «تقارير
/// البوّابة» (المشتركون حسب الزون من قائمتنا، و«تقرير الجلسات» من البوّابة)، و«الإشعارات والإعلانات» (قراءةٌ وحدها: لا تُعلَّم
/// مقروءةً في البوّابة أبداً).
///
/// وقدرات مستخدم البوّابة (`caps` + `portal_locks` من current-user بالخادم): ما لا يملكه المستخدم الذي دخل به الوكيل يبقى بمكانه
/// مقفلاً **بسببه** («لا صلاحيّة في البوّابة») لا «تعذّر» — ومنها «الإيرادات». المجهول (null) لا يُقفل شيئاً.
///
/// الأقسام الجديدة خلف المفتاح التجريبيّ للحساب (`watani_beta`، مطفأٌ افتراضاً): `lookups.data.beta` true فتظهر، وإلّا لا تظهر.
/// العقد: release_work/national_rest/contract.md (الخادم `server/watani/wataniPortalBeta.js`) — كاشٌ لكلّ حساب، وميزانيّة البوّابة
/// المشتركة (≤٣٠ نداءً/د للخادم كلّه)؛ ما لا يُعرف يصل null ويُعرض «—» لا صفراً.

int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? ''));
num? _num(dynamic v) => v is num ? v : (v == null ? null : num.tryParse(v.toString()));
String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

bool? _bool(dynamic v) {
  if (v is bool) return v;
  final s = _s(v).toLowerCase();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return null;
}

/// اسمٌ من حقلٍ قد يكون نصّاً أو `{name}` أو `{displayValue}` (البوّابة) أو `{self:{displayValue}}`.
String? _nameOf(dynamic v) {
  if (v == null) return null;
  if (v is Map) {
    final self = v['self'];
    return _sn(v['name']) ?? _sn(v['displayValue']) ?? (self is Map ? _sn(self['displayValue']) : null) ?? _sn(v['id']);
  }
  return _sn(v);
}

/// نتيجة نداء القسم: البيانات، أو قفلٌ بسببه، أو رسالة الخادم ورمزه.
///
/// القفل ([locked]): ردّ «مقفل» من الخادم (`success:true, locked:true` — مستخدم البوّابة لا يملك القسم)، أو 409 `FTTH_FORBIDDEN`،
/// أو `BETA_OFF` (القسم التجريبيّ لم يُفتح للحساب)، أو مسارٌ لا يعرفه خادمٌ أقدم — يُعرض قفلاً هادئاً بعنوانه ونصّه، لا خطأً ولا
/// قائمةً فارغة.
class NationalMoreResult<T> {
  const NationalMoreResult.ok(T this.data)
      : error = null,
        code = null,
        title = null,
        relogin = false;
  const NationalMoreResult.fail(this.error, {this.code, this.title, this.relogin = false}) : data = null;

  final T? data;
  final String? error;
  final String? code;

  /// عنوان القفل كما يرسله الخادم («لا صلاحيّة في البوّابة»).
  final String? title;
  final bool relogin;

  bool get ok => data != null;

  static const _lockCodes = {'LOCKED', 'FTTH_FORBIDDEN', 'BETA_OFF', 'NOT_AVAILABLE'};

  /// يُعرض قفلاً بسببه لا «تعذّر» ولا «إعادة المحاولة».
  bool get locked => code != null && _lockCodes.contains(code);

  /// عنوان صندوق القفل.
  String get lockTitle =>
      title ??
      switch (code) {
        'BETA_OFF' => 'قسمٌ تجريبيّ',
        'NOT_AVAILABLE' => 'غير متاحٍ بعد',
        _ => 'لا صلاحيّة في البوّابة',
      };

  /// لقائمة [NationalPaged] (تحمل النصّ وحده؛ القفل تقرؤه الشاشة من هنا قبلها).
  NationalResult<T> toResult() => ok ? NationalResult.ok(data as T) : NationalResult.fail(error, relogin: relogin);
}

/// مفاتيح الموظّف لأقسام الوطنيّ الجديدة — من كتالوج الموظّف القائم لا مفتاحٌ جديد، وهي نفسها التي يحرس بها الخادم مساراتها
/// (العقد §9، `server/providerKit/employeeRoutes.js`). والموظّف بلاها يرى القسم **بمكانه مقفلاً لا مخفيّاً**.
abstract final class NationalPerms {
  static const sessions = 'reports.sessions';
  static const team = 'reports.financial';
  static const zonesReport = 'reports.packages';
  static const sessionsReport = 'reports.sessions';
  static const notes = 'notifications.view';
}

/* ───────────────────────────── القدرات والمفتاح ───────────────────────────── */

/// ما يقوله الخادم عن هذا الحساب في البوّابة (`lookups`): المفتاح التجريبيّ ([beta])، وقدرات مستخدم البوّابة ([caps]: الاسم ⇒
/// يملك/لا؛ الغائب مجهول)، وأسباب القفل الجاهزة بالعربيّ ([locks] من `portal_locks`؛ الغائب/null متاحٌ أو مجهول).
class NationalCaps {
  const NationalCaps({this.beta = false, this.caps = const {}, this.locks = const {}, this.canWrite = false});

  final bool beta;
  final Map<String, bool> caps;
  final Map<String, String> locks;

  /// الكتابة عبر البوّابة مفتوحةٌ للحساب (`watani_portal`).
  final bool canWrite;

  /// null = مجهول (لا قفل).
  bool? cap(String k) => caps[k];

  /// البوّابة تقول صراحةً إنّ مستخدمك لا يملك هذا.
  bool denies(String k) => caps[k] == false;

  /// القسم مقفلٌ بسبب البوّابة؟ حين يُقفل **كلّ** ما يفتحه ([keys] — الإشعارات والإعلانات معاً مثلاً) بسببٍ من الخادم
  /// (`portal_locks`) أو بقدرةٍ false صراحةً. مجهولٌ واحد أو مسموحٌ واحد ⇒ مفتوح.
  bool isLocked(List<String> keys) => keys.isNotEmpty && keys.every((k) => locks.containsKey(k) || denies(k));

  /// سبب القفل لبطاقة القسم — سطرٌ واحد (الكرت لا يكبر؛ اسم القسم عنوانه، ونصّ الخادم الكامل يظهر داخل الصفحات)؛ null = مفتوح.
  String? lockOf(List<String> keys) => isLocked(keys) ? 'لا صلاحيّة في البوّابة — اطلبها من الشركة' : null;

  /// نصّ الخادم الجاهز لأوّل مفتاحٍ مقفل (أو null).
  String? lockText(List<String> keys) {
    for (final k in keys) {
      final r = locks[k];
      if (r != null) return r;
    }
    return null;
  }

  static NationalCaps fromJson(Map<String, dynamic> j) {
    final raw = j['caps'];
    final caps = <String, bool>{};
    if (raw is Map) {
      for (final e in raw.entries) {
        final b = _bool(e.value);
        if (b != null) caps[e.key.toString().trim().toLowerCase()] = b;
      }
    }
    final rr = j['portal_locks'];
    final locks = <String, String>{};
    if (rr is Map) {
      for (final e in rr.entries) {
        final t = _s(e.value);
        if (t.isNotEmpty && t.length < 300) locks[e.key.toString().trim().toLowerCase()] = t;
      }
    }
    return NationalCaps(beta: j['beta'] == true, caps: caps, locks: locks, canWrite: j['can_write'] == true);
  }
}

/// حالة «الوطنيّ» للحساب الحاليّ (المفتاح التجريبيّ والقدرات) — تُسأل حين تستمع لها القائمة (كـ«المبيعات»)، بمهلةٍ لا كلّ بناء،
/// وللوطنيّ وحده (لا نداءٌ لغيره). null = لم تصل بعد ⇒ الأقسام الجديدة لا تظهر ولا يُقفل شيء.
class NationalMoreState {
  NationalMoreState._();

  static final ValueNotifier<NationalCaps?> gate = _Gate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 10);
  static const _cooldown = Duration(seconds: 45);

  /// حسابٌ على المشروع الوطنيّ (providerKit — الزون أبٌ للمشترك).
  static bool get isNational => ProviderService.isKit && ProviderService.parentIsZone;

  static bool get beta => isNational && (gate.value?.beta ?? false);

  static Future<void> ensureFresh({bool force = false}) {
    if (!isNational) return Future<void>.value();
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = NationalMoreApi.caps().then((c) {
      if (epoch != _epoch) return;
      if (c == null) {
        _failedAt = DateTime.now();
        return;
      }
      _fetchedAt = DateTime.now();
      _failedAt = null;
      gate.value = c;
    }).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// تبديل الجلسة: لا يرى المدير التالي حال سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
  }

  @visibleForTesting
  static void debugSet(NationalCaps? c) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = c == null ? null : DateTime.now();
    gate.value = c;
  }
}

class _Gate extends ValueNotifier<NationalCaps?> {
  _Gate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(NationalMoreState.ensureFresh);
  }
}

/* ───────────────────────────── الجلسات ───────────────────────────── */

/// جلسة اشتراك: المتّصل الآن (آيبي وماك ومدّة وبايتات) أو غير المتّصل (البوّابة لا تعطيه آيبي ولا ماك ولا مدّة ⇒ null).
class NationalSession {
  const NationalSession({
    required this.username,
    this.online,
    this.customer,
    this.zone,
    this.plan,
    this.subscriptionId,
    this.startedAt,
    this.durationSec,
    this.ip,
    this.mac,
    this.download,
    this.upload,
    this.expired,
  });

  /// اسم الجهاز (يوزر الاشتراك).
  final String username;

  /// null = لا يقول الصفّ (الحالة في رأس الردّ).
  final bool? online;
  final NationalRef? customer;
  final String? zone;
  final String? plan;
  final String? subscriptionId;
  final String? startedAt;
  final int? durationSec;
  final String? ip;
  final String? mac;
  final num? download;
  final num? upload;

  /// الاشتراك منتهٍ.
  final bool? expired;

  static bool? _onlineOf(Map<String, dynamic> j) {
    final st = j['status'];
    final s = _s(st is Map ? (st['id'] ?? st['displayValue']) : st).toLowerCase();
    if (s == 'online' || s == '0') return true;
    if (s == 'offline' || s == '1') return false;
    return _bool(j['online']);
  }

  static NationalSession fromJson(Map<String, dynamic> j) {
    final sub = j['subscription'];
    final cust = j['customer'];
    final custName = cust is Map ? _sn(cust['name']) ?? _sn(cust['displayValue']) : _sn(cust);
    return NationalSession(
      username: _s(j['username']),
      online: _onlineOf(j),
      customer: custName == null ? null : NationalRef(cust is Map ? _sn(cust['id']) : null, custName),
      zone: _nameOf(j['zone']),
      plan: _sn(j['plan']) ?? (sub is Map ? _sn(sub['name']) ?? _sn(sub['displayValue']) : null),
      subscriptionId: sub is Map ? _sn(sub['id']) : _sn(j['subscription_id']),
      startedAt: _sn(j['started_at'] ?? j['createdAt']),
      durationSec: _int(j['session_time'] ?? j['sessionTimeInSeconds']),
      ip: _sn(j['ip'] ?? j['ipAddress']),
      mac: _sn(j['mac'] ?? j['macAddress']),
      download: _num(j['download_bytes'] ?? j['totalDownloadedBytes']),
      upload: _num(j['upload_bytes'] ?? j['totalUploadedBytes']),
      expired: _bool(j['expired'] ?? (sub is Map ? sub['expired'] ?? sub['isExpired'] : null)),
    );
  }
}

/* ───────────────────────────── «فريقي» ───────────────────────────── */

/// عضو فريق الحساب في البوّابة: اسمه ويوزره (أو آخر ٤ أرقام إن كان اليوزر هاتفاً) ووظيفته وحدّ محفظته وآخر دخول — **لا هاتف ولا
/// بريد** (الخادم لا يرسلهما أصلاً).
class NationalTeamMember {
  const NationalTeamMember({
    required this.name,
    this.username,
    this.usernameMasked,
    this.roleCode = '',
    this.role = '',
    this.main = false,
    this.limited,
    this.walletLimit,
    this.lastLogin,
  });

  final String name;
  final String? username;

  /// «•••4567» حين يكون اليوزر رقم هاتف.
  final String? usernameMasked;
  final String roleCode;

  /// الوظيفة بالعربيّ (من الخادم، وإلّا من رمزها).
  final String role;

  /// المستخدم الرئيسيّ للشريك (البوّابة تسمّيه «مشرف» ولا تذكر له حدّاً — «—»).
  final bool main;

  /// true = له «حدّ المحفظة» ([walletLimit])، false = «غير محدود»، null = الرئيسيّ أو لا يُعرف («—»).
  final bool? limited;
  final num? walletLimit;
  final String? lastLogin;

  String? get login => username ?? usernameMasked;

  static NationalTeamMember fromJson(Map<String, dynamic> j) {
    final role = j['role'];
    final code = role is Map ? _s(role['code'] ?? role['name']) : _s(role);
    final label = role is Map ? _sn(role['label']) ?? _sn(role['displayValue']) : null;
    final w = j['wallet_limit'];
    return NationalTeamMember(
      name: _s(j['name']),
      username: _sn(j['username']),
      usernameMasked: _sn(j['username_masked']),
      roleCode: code,
      role: label ?? nationalTeamRole(code),
      main: j['is_main'] == true,
      limited: w is Map ? _bool(w['limited']) : null,
      walletLimit: w is Map ? _num(w['amount']) : null,
      lastLogin: _sn(j['last_login_at']),
    );
  }
}

/// وظيفة عضو الفريق بأسماء البوّابة (TEAM_MEMBER_ROLES في ترجمتها) — حين لا يرسل الخادم اسمها.
String nationalTeamRole(String? code) {
  const names = {
    'contractor': 'مشرف',
    'fieldworker': 'عامل ميداني',
    'fieldworkersmanagingcustomers': 'عامل ميداني يدير المشتركين',
    'superadminmember': 'مشرف عام',
    'supportteammember': 'عضو فريق الدعم',
    'cashier': 'كاشير',
    'zoneadmin': 'مشرف منطقة',
    'regionaladminmember': 'مشرف إقليمي',
  };
  final key = (code ?? '').replaceAll(RegExp(r'[\s_-]+'), '').toLowerCase();
  return names[key] ?? (code ?? '').trim();
}

/* ───────────────────────────── «تقارير البوّابة» ───────────────────────────── */

/// زونٌ في التقرير: المشتركون (فعّال/منتهي/موقوف/المجموع — من قائمتنا) أو الجلسات (متّصل/غير متّصل). null = لم يُعرف.
class NationalZoneCount {
  const NationalZoneCount({
    required this.zone,
    this.total,
    this.active,
    this.expired,
    this.suspended,
    this.online,
    this.offline,
  });
  final String zone;
  final int? total;
  final int? active;
  final int? expired;
  final int? suspended;
  final int? online;
  final int? offline;

  static NationalZoneCount? fromJson(dynamic v) {
    if (v is! Map) return null;
    final zone = _nameOf(v['zone']) ?? _sn(v['zone_id']);
    if (zone == null) return null;
    return NationalZoneCount(
      zone: zone,
      total: _int(v['total']),
      active: _int(v['active']),
      expired: _int(v['expired']),
      suspended: _int(v['suspended']),
      online: _int(v['online']),
      offline: _int(v['offline']),
    );
  }
}

/// تقريرٌ واحد: صفوف الزونات (الأكبر أوّلاً كما يرسلها الخادم) والإجماليّات (الغائب null) — أو «جارٍ» (القائمة تُجلب بالخادم).
class NationalReport {
  const NationalReport({this.zones = const [], this.totals = const {}, this.partial = false, this.pending = false, this.fetchedAt, this.stale = false});
  final List<NationalZoneCount> zones;
  final Map<String, int?> totals;

  /// القائمة مقصوصة (حسابٌ كبير) ⇒ الأرقام من جزئها.
  final bool partial;
  final bool pending;
  final String? fetchedAt;
  final bool stale;

  int? total(String k) => totals[k];

  static NationalReport fromJson(Map<String, dynamic> b) {
    final t = b['totals'] is Map ? b['totals'] as Map : const {};
    return NationalReport(
      zones: (b['data'] is List ? b['data'] as List : const []).map(NationalZoneCount.fromJson).whereType<NationalZoneCount>().toList(),
      totals: {for (final e in t.entries) e.key.toString(): _int(e.value)},
      partial: b['partial'] == true,
      pending: b['pending'] == true,
      fetchedAt: _sn(b['fetched_at']),
      stale: b['stale'] == true,
    );
  }
}

/* ───────────────────────────── الإشعارات والإعلانات ───────────────────────────── */

/// إشعارٌ أو إعلانٌ من جرس البوّابة — النصّ عاديٌّ (الخادم ينزع وسوم HTML)، والرابط http(s) وحده.
class NationalNote {
  const NationalNote({this.id, required this.title, required this.body, this.at, this.read, this.pinned = false, this.link, this.type = ''});

  final String? id;
  final String title;
  final String body;
  final String? at;

  /// مقروءٌ في البوّابة؟ (الإشعارات وحدها) — null = لا يقول. لا نعلّمه مقروءاً أبداً.
  final bool? read;
  final bool pinned;
  final String? link;
  final String type;

  bool get unread => read == false;

  static String? _safeLink(dynamic v) {
    final s = _s(v);
    if (s.isEmpty || s.length > 600) return null;
    final u = Uri.tryParse(s);
    if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) return null;
    return s;
  }

  static NationalNote fromJson(Map<String, dynamic> j) => NationalNote(
        id: _sn(j['id']),
        title: _s(j['title']),
        body: _s(j['body']),
        at: _sn(j['at']),
        read: _bool(j['read']),
        pinned: j['pinned'] == true,
        link: _safeLink(j['link']),
        type: _s(j['type']),
      );
}

/// نوع الإشعار بالعربيّ (أسماء الموقع `ftthNotifType`) — المجهول بلا شارة.
String? nationalNoteType(String t) => const {
      'AutoRenewal': 'تجديد تلقائيّ',
      'ScheduleCancel': 'إلغاء مجدول',
      'ServiceActivation': 'تفعيل خدمة',
      'PaymentReminder': 'تذكير دفع',
      'PlanExpiry': 'انتهاء باقة',
      'ResetPassword': 'كلمة المرور',
      'ThresholdBalance': 'رصيد منخفض',
      'WalletDeduction': 'خصم من المحفظة',
      'Commission': 'عمولة',
      'WalletTopUp': 'تعبئة المحفظة',
      'WalletTransfer': 'تحويل رصيد',
      'SignatureTask': 'مهمّة توقيع',
      'InstallationTask': 'مهمّة تركيب',
      'ContractorActivation': 'تفعيل الوكيل',
      'CustomerActivation': 'تفعيل زبون',
      'CustomerApproved': 'موافقة على زبون',
    }[t.trim()];

/* ───────────────────────────── النداءات ───────────────────────────── */

class NationalMoreApi {
  NationalMoreApi._();

  /// يُسقط الفارغ — الخادم يتجاهل ما لا يعرفه ويرفض الصالح شكلاً فقط.
  @visibleForTesting
  static Map<String, dynamic> query(Map<String, Object?> m) =>
      {for (final e in m.entries) if (e.value != null && e.value.toString().isNotEmpty) e.key: e.value};

  static String _msg(dynamic b) {
    final m = b is Map ? b['message']?.toString().trim() : null;
    return (m != null && m.isNotEmpty && m.length < 300) ? m : 'تعذّر جلب البيانات من بوّابة المشروع الوطني';
  }

  static NationalMoreResult<Map<String, dynamic>> _lockedOf(Map b, {String code = 'LOCKED'}) =>
      NationalMoreResult.fail(_msg(b), code: code, title: _sn(b['title']));

  static Future<NationalMoreResult<Map<String, dynamic>>> _get(String path, Map<String, Object?> q) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(path, queryParameters: query(q));
      final b = r.data ?? const {};
      // مقفلٌ بسببه (ردّ 200): لا قائمةٌ فارغة ولا خطأ
      if (b['locked'] == true) return _lockedOf(b);
      if (b['success'] != true) return NationalMoreResult.fail(_msg(b), code: _sn(b['code']));
      return NationalMoreResult.ok(b);
    } on DioException catch (e) {
      final b = e.response?.data;
      if (!kReleaseMode) debugPrint('🔴 $path: ${e.response?.statusCode}');
      final code = b is Map ? _sn(b['code']) : null;
      if (b is Map && (b['locked'] == true || code == 'FTTH_FORBIDDEN' || code == 'BETA_OFF')) {
        return _lockedOf(b, code: code ?? 'LOCKED');
      }
      // 404 بلا رمز من خادمٍ أقدم لا يعرف المسار = القسم غير متاحٍ بعد (لا «تعذّر» يُعاد عبثاً)
      if (e.response?.statusCode == 404 && code == null) {
        return const NationalMoreResult.fail('هذا القسم غير متاحٍ لحسابك بعد — حدّث التطبيق أو انتظر تفعيله', code: 'NOT_AVAILABLE');
      }
      return NationalMoreResult.fail(_msg(b), code: code, relogin: code == 'FTTH_RELOGIN' || code == 'PROVIDER_RELOGIN');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $path: $e');
      return const NationalMoreResult.fail('تعذّر الاتّصال — أعد المحاولة');
    }
  }

  static NationalPage<T> _page<T>(Map<String, dynamic> b, T Function(Map<String, dynamic>) map) => NationalPage<T>(
        items: (b['data'] is List ? b['data'] as List : const [])
            .whereType<Map>()
            .map((m) => map(Map<String, dynamic>.from(m)))
            .toList(),
        total: _int(b['total']),
        page: _int(b['page']) ?? 1,
        pageCount: _int(b['page_count']),
        pending: b['pending'] == true,
        stale: b['stale'] == true,
        fetchedAt: _sn(b['fetched_at']),
        raw: b,
      );

  static NationalMoreResult<NationalPage<T>> _paged<T>(
          NationalMoreResult<Map<String, dynamic>> r, T Function(Map<String, dynamic>) map) =>
      r.ok
          ? NationalMoreResult.ok(_page(r.data!, map))
          : NationalMoreResult.fail(r.error, code: r.code, title: r.title, relogin: r.relogin);

  /// المفتاح التجريبيّ وقدرات مستخدم البوّابة وأسباب القفل — من `lookups` (كاشٌ ستّ ساعات بالخادم). null = تعذّر الآن.
  static Future<NationalCaps?> caps() async {
    final r = await _get('/api/v2/ftth/lookups', const {});
    if (!r.ok) return null;
    final d = r.data!['data'];
    if (d is! Map) return null;
    return NationalCaps.fromJson(Map<String, dynamic>.from(d));
  }

  /// «الجلسات»: [online] true = المتّصلون الآن، false = غير المتّصلين؛ [q] اسم الجهاز (بحثٌ بالبوّابة) أو اسم المشترك (داخل
  /// الصفحة المعروضة وحدها — `filtered_in_page`)؛ [zone] معرّف الزون. الصفحة ٢٥.
  static Future<NationalMoreResult<NationalPage<NationalSession>>> sessions({
    required bool online,
    int page = 1,
    String? q,
    String? zone,
  }) async =>
      _paged(await _get('/api/v2/ftth/sessions', sessionsQuery(online: online, page: page, q: q, zone: zone)), NationalSession.fromJson);

  @visibleForTesting
  static Map<String, Object?> sessionsQuery({required bool online, int page = 1, String? q, String? zone}) => {
        'status': online ? 'online' : 'offline',
        'page': page,
        'size': 25,
        'q': q?.trim(),
        'zone': zone,
      };

  /// «فريقي»: أعضاء فريق الحساب في البوّابة ([q] الاسم أو اليوزر).
  static Future<NationalMoreResult<NationalPage<NationalTeamMember>>> team({int page = 1, String? q}) async =>
      _paged(await _get('/api/v2/ftth/team', {'page': page, 'size': 25, 'q': q?.trim()}), NationalTeamMember.fromJson);

  static Future<NationalMoreResult<NationalReport>> _report(String path) async {
    final r = await _get(path, const {});
    return r.ok ? NationalMoreResult.ok(NationalReport.fromJson(r.data!)) : NationalMoreResult.fail(r.error, code: r.code, title: r.title, relogin: r.relogin);
  }

  /// «المشتركون حسب الزون» — من قائمة مشتركينا المكاشة بالخادم (لا نداء للبوّابة): فعّال/منتهي/موقوف لكلّ زون.
  static Future<NationalMoreResult<NationalReport>> zonesReport() => _report('/api/v2/ftth/reports/zones');

  /// «تقرير الجلسات» — من البوّابة: المتّصلون وغير المتّصلين لكلّ زون (مقفلٌ حين لا يملكه مستخدمك).
  static Future<NationalMoreResult<NationalReport>> sessionsReport() => _report('/api/v2/ftth/reports/sessions');

  /// «الإشعارات» أو «الإعلانات» ([announcements]) — للقراءة: لا شيء هنا يعلّمها مقروءةً في البوّابة.
  static Future<NationalMoreResult<NationalPage<NationalNote>>> notes({required bool announcements, int page = 1}) async =>
      _paged(
        await _get('/api/v2/ftth/notifications', {'tab': announcements ? 'announcements' : 'notifications', 'page': page, 'size': 20}),
        NationalNote.fromJson,
      );
}
