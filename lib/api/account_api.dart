import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../core/platform/store_policy.dart';
import '../core/util/server_time.dart';
import '../services/account_service.dart';
import '../services/device_id.dart';
import 'api_client.dart';

/// Pro البند ٤ — نقاط طبقة الحساب على الخادم: `/api/account/*`.
///
/// ⚠️ عميل Dio **مستقلّ** عن `ApiClient.dio`: معترضه يُلصق توكن الساس على كلّ
/// طلب، ويعدّ أيّ 401 (أو رسالةً فيها expired) انتهاءَ جلسة الساس فيمسحها.
/// هنا التوكن توكن **الحساب** في `x-account-token` (لا Authorization — حارس
/// الحظر العامّ في الخادم يفكّ أيّ Bearer)، وأخطاؤه لا تمسّ جلسة الساس.
class AccountApi {
  AccountApi._();

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiClient.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
    headers: const {'Accept': 'application/json'},
  ))
    // آيفون: رسائل الخادم الداعية للشراء («فعّل كوداً»، «رقِّ باقتك») تُنقّى
    // قبل أن تصل أيّ شاشة (App Store 3.1.1). غير آيفون: لا يلمس شيئاً.
    ..interceptors.add(StoreSafeMessagesInterceptor());

  /// منفذا الاختبار وحده (كمنفذَي `LoginScreen`): العميل — يُستبدل محوّله
  /// بخادمٍ وهميّ كما يُستبدل محوّل `ApiClient.dio` — ومصدر توكن الحساب،
  /// فـFirebase لا يعمل في `flutter test`.
  @visibleForTesting
  static Dio get dio => _dio;
  @visibleForTesting
  static Future<String?> Function({bool force}) tokenSource = AccountService.idToken;

  static Future<Response<Map<String, dynamic>>> _send(
    String method,
    String path, {
    Object? data,
  }) async {
    Future<Response<Map<String, dynamic>>> once(bool force) async {
      final token = await tokenSource(force: force);
      if (token == null) {
        throw const AccountApiException('no-account', 'account.err_signed_out', 401);
      }
      return _dio.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(method: method, headers: {
          'x-account-token': token,
          'x-device-id': await DeviceId.get(),
        }),
      );
    }

    try {
      var res = await once(false);
      final err = res.data?['error'];
      if (res.statusCode == 401 &&
          (err == 'account-token-expired' || err == 'invalid-account-token')) {
        res = await once(true); // توكنٌ قديم بعد تأكيد البريد/انقضاء الساعة
      }
      return res;
    } on DioException catch (e) {
      throw AccountApiException('network', 'account.err_network', e.response?.statusCode ?? 0);
    }
  }

  static AccountApiException _fail(Response<Map<String, dynamic>> res) {
    final b = res.data ?? const {};
    final code = (b['error'] ?? 'error').toString();
    final msg = (b['message'] as String?)?.trim();
    return AccountApiException(code, msg?.isNotEmpty == true ? msg! : _keyFor(code), res.statusCode ?? 0);
  }

  static String _keyFor(String code) => switch (code) {
        'email-not-verified' => 'account.err_not_verified',
        'account-disabled' => 'account.err_account_disabled',
        'auth-unavailable' => 'account.err_network',
        // توكن الحساب رُفض حتى بعد تجديده — «سجّل الدخول من جديد» لا «حدث خطأ».
        'no-account-token' || 'invalid-account-token' || 'account-token-expired' =>
          'account.err_signed_out',
        _ => 'account.err_generic',
      };

  /// أوّل دخول (ببريدٍ مؤكَّد): ينشئ الحساب، والتجربة ١٤ يوماً إن لم يأخذها
  /// البريد سابقاً. تكراره آمن (لا يجدّد التجربة).
  static Future<AccountMe> bootstrap() async {
    final res = await _send('POST', '/api/account/bootstrap');
    if (res.statusCode != 200) throw _fail(res);
    return AccountMe.fromJson(res.data ?? const {});
  }

  static Future<AccountMe> me() async {
    final res = await _send('GET', '/api/account/me');
    if (res.statusCode != 200) throw _fail(res);
    return AccountMe.fromJson(res.data ?? const {});
  }

  /// تفعيل كود. الخادم يطبّع ما يكتبه المستخدم (شرطات، أرقام عربيّة…).
  static Future<AccountSubscription> redeemCode(String code) async {
    final res = await _send('POST', '/api/account/redeem-code', data: {'code': code});
    final b = res.data ?? const {};
    if (res.statusCode == 200 && b['ok'] == true) {
      final s = b['subscription'];
      return s is Map<String, dynamic>
          ? AccountSubscription.fromJson(s)
          : (await me()).subscription;
    }
    final code0 = (b['error'] ?? 'error').toString();
    throw AccountApiException(code0, _redeemKey(code0), res.statusCode ?? 0);
  }

  static String _redeemKey(String code) => switch (code) {
        'empty-code' => 'account.code_empty',
        'not-found' || 'invalid-code' => 'account.code_not_found',
        'already-used' => 'account.code_used',
        'revoked' => 'account.code_revoked',
        'too-many-attempts' => 'account.err_too_many',
        'in-progress' => 'account.code_in_progress',
        'no-account' => 'account.err_generic',
        _ => 'account.err_generic',
      };

  static Future<List<LinkedCompany>> companies() async {
    final res = await _send('GET', '/api/account/companies');
    if (res.statusCode != 200) throw _fail(res);
    final list = res.data?['companies'];
    return list is List
        ? list.whereType<Map<String, dynamic>>().map(LinkedCompany.fromJson).toList()
        : const [];
  }

  /// دليل الشركات المعروفة (يضبطه المالك) — «إضافة شركة» تختار منه.
  static Future<List<DirectoryCompany>> sasDirectory() async {
    final res = await _send('GET', '/api/account/sas-directory');
    if (res.statusCode != 200) throw _fail(res);
    final list = res.data?['companies'];
    return list is List
        ? list.whereType<Map<String, dynamic>>().map(DirectoryCompany.fromJson).where((c) => c.url.isNotEmpty).toList()
        : const [];
  }

  static Future<void> removeCompany(LinkedCompany c) async {
    final res = await _send('POST', '/api/account/companies/remove',
        data: {'sasCode': c.sasCode, 'username': c.username});
    if (res.statusCode != 200 && res.statusCode != 404) throw _fail(res);
  }

  // ───────────── حذف الحساب (إرشاد أبل 5.1.1(v)) ─────────────

  /// يحذف حساب Pro على الخادم: الحساب وربط شركاته وأجهزته المسجّلة. بيانات
  /// الساس ومشتركوه لا تُمسّ (هي ملك الساس لا الحساب).
  ///
  /// النجاح: 200 (ما لم يقل `ok:false`)، أو 404 `no-account` — الحساب محذوفٌ
  /// سلفاً (من جهازٍ آخر)، والنتيجة التي أرادها المستخدم حاصلة. أيّ 404 آخر
  /// (مسارٌ غير منشور مثلاً) **خطأ** لا نجاح: لا نُبلغ «حُذف» ولم يُحذف شيء.
  /// خطأ الخادم (٥xx) يُقرأ «تعذّر الحذف الآن» لا «تأكّد من الإنترنت».
  static Future<void> deleteAccount() async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _send('POST', '/api/account/delete');
    } on AccountApiException catch (e) {
      if (e.code == 'network' && e.status >= 500) {
        throw AccountApiException('server-error', 'account.delete_err_server', e.status);
      }
      rethrow;
    }
    final b = res.data ?? const {};
    final status = res.statusCode ?? 0;
    final code = (b['error'] ?? '').toString();
    if (status == 200 && b['ok'] != false) return;
    if (status == 404 && code == 'no-account') return;
    final msg = (b['message'] as String?)?.trim();
    throw AccountApiException(
      code.isEmpty ? 'delete-failed' : code,
      msg?.isNotEmpty == true ? msg! : _deleteKey(code),
      status,
    );
  }

  static String _deleteKey(String code) => switch (code) {
        'requires-recent-login' || 'recent-login-required' => 'account.delete_err_recent_login',
        'too-many-attempts' => 'account.err_too_many',
        'in-progress' => 'account.delete_err_in_progress',
        'account-disabled' => 'account.err_account_disabled',
        'auth-unavailable' => 'account.delete_err_server',
        'no-account-token' || 'invalid-account-token' || 'account-token-expired' =>
          'account.err_signed_out',
        _ => 'account.delete_failed',
      };

  // ───────────── «أجهزتي» (حدّ الأجهزة = شركات الباقة + ١) ─────────────

  /// الأجهزة النشطة للحساب (ظهرت خلال ٣٠ يوماً) وحدّها.
  ///
  /// بتوكن الحساب وحده: حدّ الأجهزة يُفحص عند دخول الساس وتجديد توكنه لا
  /// هنا، فتعمل والجهاز نفسه مرفوضٌ عند الحدّ — وهي مخرجه الوحيد منه.
  /// «هذا الجهاز» كما يراه الخادم (`current` = معرّف `x-device-id`)، وإن لم
  /// يُرسله فمعرّفنا المحلّيّ — هو نفسه ما أُرسل.
  static Future<AccountDevices> listDevices() async {
    final res = await _devicesCall('GET', '/api/account/devices', 'account.devices_err_load');
    final b = res.data ?? const {};
    final server = b['current']?.toString().trim() ?? '';
    return AccountDevices.fromJson(b, currentId: server.isNotEmpty ? server : await DeviceId.get());
  }

  /// يزيل جهازاً من الحساب فيتحرّر مكانه فوراً. يُرجع القائمة بعد الإزالة
  /// (null إن لم يُرسلها الخادم ← يُعاد الجلب). 404 = أُزيل سابقاً من جهازٍ
  /// آخر — والنتيجة التي أرادها المستخدم حاصلة، فليست خطأً.
  static Future<List<AccountDevice>?> removeDevice(String deviceId) async {
    final res = await _devicesCall('POST', '/api/account/devices/remove', 'account.devices_err_remove',
        data: {'deviceId': deviceId}, ok404: true);
    return AccountDevices.parseList(res.data?['devices']);
  }

  /// نداءٌ لـ«أجهزتي» برسالةٍ تخصّه: خطأ الخادم (٥xx يرميه Dio فيصل «شبكةً»
  /// من [_send]) يُقرأ «تعذّر تحميل الأجهزة الآن» لا «تأكّد من الإنترنت» —
  /// الإنترنت سليم، والمستخدم العالق عند الحدّ لا يحتاج تشخيصاً خاطئاً.
  static Future<Response<Map<String, dynamic>>> _devicesCall(
    String method,
    String path,
    String serverErrorKey, {
    Object? data,
    bool ok404 = false,
  }) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _send(method, path, data: data);
    } on AccountApiException catch (e) {
      if (e.code == 'network' && e.status >= 500) {
        throw AccountApiException('server-error', serverErrorKey, e.status);
      }
      rethrow;
    }
    final s = res.statusCode ?? 0;
    if (s == 200 || (ok404 && s == 404)) return res;
    throw _fail(res);
  }
}

class AccountApiException implements Exception {
  const AccountApiException(this.code, this.message, this.status);

  /// رمز الخادم (`email-not-verified`، `subscription-ended`…) أو `network`.
  final String code;

  /// رسالة الخادم العربيّة، أو مفتاح ترجمة (يبدأ بـ`account.`).
  final String message;
  final int status;

  bool get isNetwork => code == 'network' || status == 503;

  @override
  String toString() => 'AccountApiException($code, $status)';
}

class AccountSubscription {
  const AccountSubscription({
    required this.status,
    required this.active,
    required this.daysLeft,
    this.endsAt,
    this.trialEndsAt,
    this.validUntil,
    this.maxDevices,
    this.devicesUsed,
  });

  /// none | trial | active | expired
  final String status;
  final bool active;
  final int daysLeft;
  final DateTime? endsAt;
  final DateTime? trialEndsAt;
  final DateTime? validUntil;

  /// حدّ الأجهزة (شركات الباقة + ١) والأجهزة النشطة الآن — null إن لم
  /// يُرسلهما الخادم (نسخةٌ أقدم).
  final int? maxDevices;
  final int? devicesUsed;

  bool get isTrial => status == 'trial';

  /// البريد أخذ تجربته سابقاً (بحسابٍ آخر) — لا تجربة لهذا الحساب.
  bool get trialUsedElsewhere => status == 'expired' && trialEndsAt == null && validUntil == null;

  static DateTime? _d(Object? v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  factory AccountSubscription.fromJson(Map<String, dynamic> j) => AccountSubscription(
        status: (j['status'] ?? 'none').toString(),
        active: j['active'] == true,
        daysLeft: (j['daysLeft'] as num?)?.toInt() ?? 0,
        endsAt: _d(j['endsAt']),
        trialEndsAt: _d(j['trialEndsAt']),
        validUntil: _d(j['validUntil']),
        maxDevices: _limit(j['maxDevices']),
        devicesUsed: _count(j['devicesUsed']),
      );
}

/// عددٌ صحيح غير سالب من ردّ الخادم (رقمٌ أو نصّ)، وإلّا null.
int? _count(Object? v) {
  final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
  return n != null && n >= 0 ? n : null;
}

/// حدٌّ موجب، وإلّا null — ٠ ليس حدّاً بل غيابه.
int? _limit(Object? v) {
  final n = _count(v);
  return n != null && n > 0 ? n : null;
}

/// جهازٌ دخل بالحساب — صفٌّ من `GET /api/account/devices`.
class AccountDevice {
  const AccountDevice({required this.deviceId, this.label, this.createdAt, this.lastSeenAt});

  final String deviceId;

  /// اسمٌ من الخادم — لا يضعه اليوم (العمود موجود)؛ وغيابه ← «جهاز» + [shortId].
  final String? label;

  /// أوّل دخول (تسجيل الجهاز) وآخر نشاط (آخر دخول ساسٍ أو تجديد توكنٍ منه).
  final DateTime? createdAt;
  final DateTime? lastSeenAt;

  /// معرّفٌ قصير للعرض حين لا اسم: أوّل ستّة محارف بأحرفٍ كبيرة — يكفي
  /// لتمييز أجهزة حسابٍ واحد بعضها عن بعض.
  String get shortId {
    final s = deviceId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return (s.length > 6 ? s.substring(0, 6) : s).toUpperCase();
  }

  factory AccountDevice.fromJson(Map<String, dynamic> j) {
    final label = j['label']?.toString().trim() ?? '';
    return AccountDevice(
      deviceId: (j['deviceId'] ?? '').toString().trim(),
      label: label.isEmpty ? null : label,
      // توقيتات جدولنا (موسومة UTC) ← بتوقيت الجهاز.
      createdAt: parseServerUtc(j['createdAt']?.toString()),
      lastSeenAt: parseServerUtc(j['lastSeenAt']?.toString()),
    );
  }
}

/// ردّ «أجهزتي»: القائمة + الحدّ + معرّف هذا الجهاز.
class AccountDevices {
  const AccountDevices({required this.devices, this.maxDevices, this.currentId});

  /// الأحدث نشاطاً أوّلاً (ترتيب الخادم).
  final List<AccountDevice> devices;

  /// حدّ الباقة. null = لم يُرسله الخادم.
  final int? maxDevices;

  /// معرّف هذا الجهاز (`x-device-id`).
  final String? currentId;

  bool isCurrent(AccountDevice d) => currentId != null && d.deviceId == currentId;

  /// هذا الجهاز مسجَّلٌ في الحساب. غيابه عند امتلاء الحدّ = سبب الرفض.
  bool get hasCurrent => devices.any(isCurrent);

  /// الحدّ ممتلئ: جهازٌ جديد لا يدخل حتى يُزال أحدها.
  bool get full => maxDevices != null && devices.length >= maxDevices!;

  AccountDevices withDevices(List<AccountDevice> list) =>
      AccountDevices(devices: list, maxDevices: maxDevices, currentId: currentId);

  /// null حين ليست قائمةً أصلاً (لا «قائمة فارغة» صامتة).
  static List<AccountDevice>? parseList(Object? raw) => raw is List
      ? raw
          .whereType<Map>()
          .map((m) => AccountDevice.fromJson(m.cast<String, dynamic>()))
          .where((d) => d.deviceId.isNotEmpty)
          .toList()
      : null;

  factory AccountDevices.fromJson(Map<String, dynamic> j, {String? currentId}) => AccountDevices(
        devices: parseList(j['devices']) ?? const [],
        maxDevices: _limit(j['maxDevices']),
        currentId: currentId,
      );
}

/// «تواصل معنا» — يضبطها المالك من لوحته (لا تُكتب في التطبيق).
class SupportInfo {
  const SupportInfo({this.telegram, this.whatsapp});

  /// اسم مستخدم تيليجرام بلا @.
  final String? telegram;

  /// رقمٌ دوليّ بلا + (مثلاً 9647XXXXXXXXX).
  final String? whatsapp;

  bool get isEmpty => (telegram ?? '').isEmpty && (whatsapp ?? '').isEmpty;

  static String? _s(Object? v) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? null : t;
  }

  factory SupportInfo.fromJson(Map<String, dynamic>? j) =>
      SupportInfo(telegram: _s(j?['telegram']), whatsapp: _s(j?['whatsapp']));
}

class AccountMe {
  const AccountMe({
    required this.registered,
    required this.email,
    required this.accountStatus,
    required this.subscription,
    this.support = const SupportInfo(),
  });

  final bool registered;
  final String? email;
  final String? accountStatus;
  final AccountSubscription subscription;
  final SupportInfo support;

  bool get disabled => accountStatus == 'disabled';

  factory AccountMe.fromJson(Map<String, dynamic> j) => AccountMe(
        registered: j['registered'] == true,
        email: j['email']?.toString(),
        accountStatus: j['accountStatus']?.toString(),
        subscription: AccountSubscription.fromJson(
            (j['subscription'] as Map?)?.cast<String, dynamic>() ?? const {}),
        support: SupportInfo.fromJson((j['support'] as Map?)?.cast<String, dynamic>()),
      );
}

class LinkedCompany {
  const LinkedCompany({
    required this.sasCode,
    required this.sasUrl,
    required this.username,
    required this.label,
    required this.role,
    this.lastLoginAt,
  });

  final String sasCode;

  /// رابط الساس كما يعرفه الخادم — يُرسَل مع الدخول فيصل الساس الصحيح.
  final String? sasUrl;
  final String username;
  final String label;

  /// admin | employee
  final String role;
  final DateTime? lastLoginAt;

  bool get isEmployee => role == 'employee';

  factory LinkedCompany.fromJson(Map<String, dynamic> j) => LinkedCompany(
        sasCode: (j['sasCode'] ?? '').toString(),
        sasUrl: j['sasUrl']?.toString(),
        username: (j['username'] ?? '').toString(),
        label: (j['label'] ?? j['sasCode'] ?? '').toString(),
        role: (j['role'] ?? 'admin').toString(),
        lastLoginAt: j['lastLoginAt'] == null
            ? null
            : DateTime.tryParse(j['lastLoginAt'].toString())?.toLocal(),
      );
}

class DirectoryCompany {
  const DirectoryCompany({required this.code, required this.name, required this.url});
  final String code;
  final String name;
  final String url;

  String get host => Uri.tryParse(url)?.host ?? url;

  factory DirectoryCompany.fromJson(Map<String, dynamic> j) => DirectoryCompany(
        code: (j['code'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
      );
}
