import 'package:dio/dio.dart';

import '../services/account_service.dart';
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
  ));

  static Future<Response<Map<String, dynamic>>> _send(
    String method,
    String path, {
    Object? data,
  }) async {
    Future<Response<Map<String, dynamic>>> once(bool force) async {
      final token = await AccountService.idToken(force: force);
      if (token == null) {
        throw const AccountApiException('no-account', 'account.err_signed_out', 401);
      }
      return _dio.request<Map<String, dynamic>>(
        path,
        data: data,
        options: Options(method: method, headers: {'x-account-token': token}),
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
  });

  /// none | trial | active | expired
  final String status;
  final bool active;
  final int daysLeft;
  final DateTime? endsAt;
  final DateTime? trialEndsAt;
  final DateTime? validUntil;

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
